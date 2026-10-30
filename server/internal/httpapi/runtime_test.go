package httpapi

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/growth"
	"skillatlas/internal/skill"
	"skillatlas/internal/task"
	"skillatlas/internal/testdb"
	"strconv"
	"syscall"
	"testing"
	"time"
)

func TestI1ActualAPIProcessAndRestart(t *testing.T) {
	db := testdb.Open(t)
	directory := t.TempDir()
	serverRoot, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(directory, "skillatlas-api")
	build := exec.Command(filepath.Join(runtime.GOROOT(), "bin", "go"), "build", "-o", binary, "./cmd/api")
	build.Dir = serverRoot
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("构建实际 API 失败：%s", output)
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "localhost"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(24 * time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, BasicConstraintsValid: true, DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}}
	certificate, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certificate})
	private, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	certPath, keyPath := filepath.Join(directory, "cert.pem"), filepath.Join(directory, "key.pem")
	if err = os.WriteFile(certPath, certPEM, 0644); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(keyPath, pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: private}), 0600); err != nil {
		t.Fatal(err)
	}
	address, err := url.Parse(os.Getenv("TEST_DATABASE_URL"))
	if err != nil {
		t.Fatal("测试数据库地址无效")
	}
	query := address.Query()
	query.Set("search_path", db.Config().ConnConfig.RuntimeParams["search_path"])
	address.RawQuery = query.Encode()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	baseURL := "https://localhost:" + strconv.Itoa(port)
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(certPEM)
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 3 * time.Second}
	var process *exec.Cmd
	var done chan error
	var log *os.File
	stop := func() {
		if process == nil {
			return
		}
		process.Process.Signal(syscall.SIGTERM)
		select {
		case err := <-done:
			if err != nil {
				t.Errorf("API 正常退出失败：%v", err)
			}
		case <-time.After(5 * time.Second):
			process.Process.Kill()
			<-done
			t.Error("API 未按时退出")
		}
		log.Close()
		process = nil
	}
	t.Cleanup(stop)
	start := func() {
		process = exec.Command(binary)
		process.Env = append(os.Environ(), "DATABASE_URL="+address.String(), "LISTEN_ADDR=127.0.0.1:"+strconv.Itoa(port), "TLS_CERT="+certPath, "TLS_KEY="+keyPath)
		log, err = os.Create(filepath.Join(directory, "api.log"))
		if err != nil {
			t.Fatal(err)
		}
		process.Stdout = log
		process.Stderr = log
		if err = process.Start(); err != nil {
			t.Fatal(err)
		}
		done = make(chan error, 1)
		go func() { done <- process.Wait() }()
		deadline := time.Now().Add(10 * time.Second)
		for time.Now().Before(deadline) {
			response, err := client.Get(baseURL + "/health")
			if err == nil {
				response.Body.Close()
				if response.StatusCode == 200 {
					return
				}
			}
			time.Sleep(50 * time.Millisecond)
		}
		t.Fatal("实际 API 未在时限内就绪")
	}
	request := func(method, path, token string, input any, status int) []byte {
		var data []byte
		if input != nil {
			data, err = json.Marshal(input)
			if err != nil {
				t.Fatal(err)
			}
		}
		req, err := http.NewRequest(method, baseURL+path, bytes.NewReader(data))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		response, err := client.Do(req)
		if err != nil {
			t.Fatalf("实际 HTTPS 请求失败：%v", err)
		}
		defer response.Body.Close()
		body, err := io.ReadAll(io.LimitReader(response.Body, 2<<20))
		if err != nil {
			t.Fatal(err)
		}
		if response.StatusCode != status {
			t.Fatalf("%s %s 状态=%d，期望=%d", method, path, response.StatusCode, status)
		}
		return body
	}
	start()
	one := decodeData[auth.Session](t, request("POST", "/v1/auth/register", "", auth.Credentials{Email: "i1-owner@example.invalid", Password: "SkillAtlas-I1-only-2026", Timezone: "Asia/Shanghai"}, 201))
	two := decodeData[auth.Session](t, request("POST", "/v1/auth/register", "", auth.Credentials{Email: "i1-other@example.invalid", Password: "SkillAtlas-I1-only-2026", Timezone: "UTC"}, 201))
	tr := decodeData[skill.Tree](t, request("POST", "/v1/skill-trees", one.Token, skill.TreeInput{ID: apiutil.ID(), Name: "I1 后端", ThemeKey: "blue"}, 201))
	sk := decodeData[skill.Skill](t, request("POST", "/v1/skills", one.Token, skill.SkillInput{ID: apiutil.ID(), TreeID: tr.ID, Name: "Go", IconKey: "code"}, 201))
	item := decodeData[task.Task](t, request("POST", "/v1/tasks", one.Token, task.Input{ID: apiutil.ID(), Title: "I1 实际接口", Status: "todo", Skills: []task.Binding{{SkillID: sk.ID, RewardLevels: 1}}}, 201))
	first, second := focusInput(sk.ID, 20), focusInput(sk.ID, 50)
	first.TaskID = &item.ID
	second.TaskID = &item.ID
	request("POST", "/v1/focus-sessions", one.Token, first, 201)
	request("POST", "/v1/focus-sessions", one.Token, second, 201)
	request("POST", "/v1/focus-sessions", one.Token, first, 201)
	conflict := first
	conflict.EffectiveSeconds = 21
	request("POST", "/v1/focus-sessions", one.Token, conflict, 409)
	foreign := focusInput(sk.ID, 60)
	request("POST", "/v1/focus-sessions", two.Token, foreign, 404)
	before := decodeData[growth.Progress](t, request("GET", "/v1/skills/"+sk.ID+"/progress", one.Token, nil, 200))
	if before.TotalFocusSeconds != 70 || before.TimeXP != 1 || before.Level != 1 {
		t.Fatal("实际 HTTP 链路 XP 不正确")
	}
	stop()
	transport.CloseIdleConnections()
	start()
	after := decodeData[growth.Progress](t, request("GET", "/v1/skills/"+sk.ID+"/progress", one.Token, nil, 200))
	if after.TotalFocusSeconds != 70 || after.TimeXP != 1 {
		t.Fatal("进程重启后持久化不一致")
	}
	var sessions, events int
	if err = db.QueryRow(context.Background(), `SELECT count(*) FROM focus_sessions WHERE user_id=$1`, one.User.ID).Scan(&sessions); err != nil {
		t.Fatal(err)
	}
	if err = db.QueryRow(context.Background(), `SELECT count(*) FROM growth_events WHERE user_id=$1`, one.User.ID).Scan(&events); err != nil {
		t.Fatal(err)
	}
	if sessions != 2 || events != 2 {
		t.Fatal("重放或冲突产生额外副作用")
	}
	t.Log("I1：真实 API 二进制进程 → HTTPS → 隔离 PostgreSQL；20+50 秒=1 XP、重放/冲突/越权拒绝、真实进程重启保持一致。")
}
