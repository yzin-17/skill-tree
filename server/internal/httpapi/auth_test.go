package httpapi

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"skillatlas/internal/auth"
	"skillatlas/internal/testdb"
)

func call(t *testing.T, s *Server, method, path, token string, input any, want int) []byte {
	t.Helper()
	var body []byte
	if input != nil {
		body, _ = json.Marshal(input)
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(body))
	req.RemoteAddr = "127.0.0.1:10000"
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	recorder := httptest.NewRecorder()
	s.ServeHTTP(recorder, req)
	if recorder.Code != want {
		t.Fatalf("%s %s: status=%d want=%d", method, path, recorder.Code, want)
	}
	if recorder.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("认证响应应禁止缓存")
	}
	return recorder.Body.Bytes()
}
func decodeData[T any](t *testing.T, data []byte) T {
	t.Helper()
	var envelope struct {
		Data T `json:"data"`
	}
	if err := json.Unmarshal(data, &envelope); err != nil {
		t.Fatal(err)
	}
	return envelope.Data
}
func TestAuthOwnershipAndTokenLifecycle(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	ctx := context.Background()
	bytes, err := os.ReadFile("../../contracts/auth.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var contract struct {
		Fixtures []auth.Credentials `json:"fixtures"`
	}
	if err = json.Unmarshal(bytes, &contract); err != nil {
		t.Fatal(err)
	}
	one := decodeData[auth.Session](t, call(t, s, "POST", "/v1/auth/register", "", contract.Fixtures[0], 201))
	call(t, s, "POST", "/v1/auth/register", "", contract.Fixtures[0], 409)
	two := decodeData[auth.Session](t, call(t, s, "POST", "/v1/auth/register", "", contract.Fixtures[1], 201))
	if one.User.ID == two.User.ID || len(one.Token) != 43 {
		t.Fatal("账号与会话不正确")
	}
	call(t, s, "GET", "/v1/me", "", nil, 401)
	call(t, s, "GET", "/v1/me?user_id="+two.User.ID, one.Token, nil, 400)
	me := decodeData[auth.User](t, call(t, s, "GET", "/v1/me", one.Token, nil, 200))
	if me.ID != one.User.ID {
		t.Fatal("身份错误")
	}
	if auth.RequireOwner(one.User, two.User.ID) == nil || auth.RequireOwner(one.User, one.User.ID) != nil {
		t.Fatal("资源归属检查失败")
	}
	call(t, s, "POST", "/v1/auth/register", "", map[string]string{"email": "forged@example.invalid", "password": "SkillAtlas-test-only-2026", "user_id": two.User.ID}, 400)
	bad := contract.Fixtures[0]
	bad.Password = "incorrect-password"
	call(t, s, "POST", "/v1/auth/login", "", bad, 401)
	again := decodeData[auth.Session](t, call(t, s, "POST", "/v1/auth/login", "", contract.Fixtures[0], 200))
	if again.Token == one.Token || again.User.ID != one.User.ID {
		t.Fatal("登录应生成独立会话")
	}
	var password string
	var stored []byte
	if err = db.QueryRow(ctx, `SELECT password_hash FROM users WHERE id=$1`, one.User.ID).Scan(&password); err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256([]byte(one.Token))
	if err = db.QueryRow(ctx, `SELECT token_hash FROM auth_sessions WHERE token_hash=$1`, digest[:]).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(password, "argon2id$") || strings.Contains(password, contract.Fixtures[0].Password) || string(stored) == one.Token {
		t.Fatal("凭据存储不安全")
	}
	call(t, s, "POST", "/v1/auth/logout", one.Token, nil, 200)
	call(t, s, "POST", "/v1/auth/logout", one.Token, nil, 200)
	call(t, s, "GET", "/v1/me", one.Token, nil, 401)
	call(t, s, "GET", "/v1/me", again.Token, nil, 200)
	hash := sha256.Sum256([]byte(again.Token))
	if _, err = db.Exec(ctx, `UPDATE auth_sessions SET expires_at=now()-interval '1 minute' WHERE token_hash=$1`, hash[:]); err != nil {
		t.Fatal(err)
	}
	call(t, s, "GET", "/v1/me", again.Token, nil, 401)
	for _, path := range []string{"/v1/me", "/v1/me?user_id=" + one.User.ID} {
		response := call(t, s, "GET", path, two.Token, nil, map[bool]int{true: 400, false: 200}[strings.Contains(path, "?")])
		if strings.Contains(string(response), "password_hash") || strings.Contains(string(response), two.Token) {
			t.Fatal("响应泄露凭据")
		}
	}
}
