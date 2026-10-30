package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"net"
	"net/http"
	"net/mail"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"skillatlas/internal/apiutil"
)

type User struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	Timezone  string    `json:"timezone"`
	CreatedAt time.Time `json:"created_at"`
}
type Session struct {
	User      User      `json:"user"`
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
}
type Credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Timezone string `json:"timezone,omitempty"`
}
type contextKey struct{}
type allowance struct {
	Start time.Time
	Count int
}
type Service struct {
	DB       *pgxpool.Pool
	mutex    sync.Mutex
	attempts map[string]allowance
	work     chan struct{}
	dummy    string
}

func New(db *pgxpool.Pool) *Service {
	dummy, _ := hashPassword(apiutil.ID())
	return &Service{DB: db, attempts: make(map[string]allowance), work: make(chan struct{}, 4), dummy: dummy}
}
func (s *Service) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/auth/register", s.signUp)
	mux.HandleFunc("POST /v1/auth/login", s.login)
	mux.HandleFunc("POST /v1/auth/logout", s.logout)
	mux.HandleFunc("GET /v1/me", s.Require(s.me))
	mux.HandleFunc("PATCH /v1/me", s.Require(s.updateMe))
}
func Current(ctx context.Context) User { return ctx.Value(contextKey{}).(User) }
func RequireOwner(user User, owner string) error {
	if user.ID != owner {
		return apiutil.NotFound()
	}
	return nil
}
func tokenHash(token string) []byte { value := sha256.Sum256([]byte(token)); return value[:] }
func bearer(r *http.Request) string {
	fields := strings.Fields(r.Header.Get("Authorization"))
	if len(fields) != 2 || fields[0] != "Bearer" || len(fields[1]) != 43 {
		return ""
	}
	return fields[1]
}
func (s *Service) Require(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Has("user_id") {
			apiutil.WriteError(w, apiutil.Fail(400, "identity_override", "账号身份由当前登录确定，不接受 user_id 参数。"))
			return
		}
		token := bearer(r)
		var user User
		err := s.DB.QueryRow(r.Context(), `SELECT u.id::text,u.email,u.timezone,u.created_at FROM users u JOIN auth_sessions a ON a.user_id=u.id WHERE a.token_hash=$1 AND a.revoked_at IS NULL AND a.expires_at>now()`, tokenHash(token)).Scan(&user.ID, &user.Email, &user.Timezone, &user.CreatedAt)
		if token == "" || errors.Is(err, pgx.ErrNoRows) {
			apiutil.WriteError(w, apiutil.Fail(401, "unauthenticated", "请重新登录。"))
			return
		}
		if err != nil {
			apiutil.WriteError(w, err)
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), contextKey{}, user)))
	}
}
func (s *Service) throttle(w http.ResponseWriter, r *http.Request) bool {
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	now := time.Now()
	s.mutex.Lock()
	for key, value := range s.attempts {
		if now.Sub(value.Start) > 5*time.Minute {
			delete(s.attempts, key)
		}
	}
	value := s.attempts[host]
	if value.Start.IsZero() {
		value.Start = now
	}
	value.Count++
	s.attempts[host] = value
	s.mutex.Unlock()
	if value.Count > 20 {
		w.Header().Set("Retry-After", "300")
		apiutil.WriteError(w, apiutil.Fail(429, "rate_limited", "尝试过于频繁，请稍后再试。"))
		return false
	}
	select {
	case s.work <- struct{}{}:
		return true
	default:
		apiutil.WriteError(w, apiutil.Fail(429, "busy", "正在处理登录，请稍后再试。"))
		return false
	}
}
func validate(input *Credentials, registration bool) error {
	input.Email = strings.ToLower(strings.TrimSpace(input.Email))
	address, err := mail.ParseAddress(input.Email)
	if err != nil || address.Address != input.Email || len(input.Email) > 254 {
		return apiutil.Fail(400, "invalid_email", "请输入有效邮箱。")
	}
	size := utf8.RuneCountInString(input.Password)
	if size < 12 || size > 128 {
		return apiutil.Fail(400, "invalid_password", "密码需要 12–128 个字符。")
	}
	if registration {
		if input.Timezone == "" {
			input.Timezone = "Asia/Shanghai"
		}
		if _, err := time.LoadLocation(input.Timezone); err != nil {
			return apiutil.Fail(400, "invalid_timezone", "时区必须为有效 IANA 标识。")
		}
	}
	return nil
}
func (s *Service) session(ctx context.Context, tx pgx.Tx, user User) (Session, error) {
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		return Session{}, err
	}
	token := base64.RawURLEncoding.EncodeToString(secret)
	expires := time.Now().UTC().Add(30 * 24 * time.Hour)
	_, err := tx.Exec(ctx, `INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES($1,$2,$3)`, tokenHash(token), user.ID, expires)
	return Session{User: user, Token: token, ExpiresAt: expires}, err
}
func (s *Service) signUp(w http.ResponseWriter, r *http.Request) {
	if !s.throttle(w, r) {
		return
	}
	defer func() { <-s.work }()
	var input Credentials
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if err := validate(&input, true); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	password, err := hashPassword(input.Password)
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	defer tx.Rollback(r.Context())
	user := User{ID: apiutil.ID(), Email: input.Email, Timezone: input.Timezone}
	err = tx.QueryRow(r.Context(), `INSERT INTO users(id,email,password_hash,timezone) VALUES($1,$2,$3,$4) RETURNING created_at`, user.ID, user.Email, password, user.Timezone).Scan(&user.CreatedAt)
	var conflict *pgconn.PgError
	if errors.As(err, &conflict) && conflict.Code == "23505" {
		apiutil.WriteError(w, apiutil.Fail(409, "email_exists", "该邮箱已注册，请登录。"))
		return
	}
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	session, err := s.session(r.Context(), tx, user)
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 201, session)
}
func (s *Service) login(w http.ResponseWriter, r *http.Request) {
	if !s.throttle(w, r) {
		return
	}
	defer func() { <-s.work }()
	var input Credentials
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if err := validate(&input, false); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	var user User
	var encoded string
	err := s.DB.QueryRow(r.Context(), `SELECT id::text,email,timezone,created_at,password_hash FROM users WHERE email=$1`, input.Email).Scan(&user.ID, &user.Email, &user.Timezone, &user.CreatedAt, &encoded)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		apiutil.WriteError(w, err)
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		encoded = s.dummy
	}
	verified := verifyPassword(encoded, input.Password)
	if user.ID == "" || !verified {
		apiutil.WriteError(w, apiutil.Fail(401, "invalid_credentials", "邮箱或密码不正确。"))
		return
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	defer tx.Rollback(r.Context())
	session, err := s.session(r.Context(), tx, user)
	if err == nil {
		err = tx.Commit(r.Context())
	}
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, session)
}
func (s *Service) logout(w http.ResponseWriter, r *http.Request) {
	token := bearer(r)
	if token == "" {
		apiutil.WriteError(w, apiutil.Fail(401, "unauthenticated", "请提供登录凭据。"))
		return
	}
	_, err := s.DB.Exec(r.Context(), `UPDATE auth_sessions SET revoked_at=COALESCE(revoked_at,now()) WHERE token_hash=$1`, tokenHash(token))
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, map[string]bool{"logged_out": true})
}
func (s *Service) me(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Has("user_id") {
		apiutil.WriteError(w, apiutil.Fail(400, "identity_override", "身份只能来自登录凭据。"))
		return
	}
	apiutil.Write(w, 200, Current(r.Context()))
}
func (s *Service) updateMe(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Timezone string `json:"timezone"`
	}
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if input.Timezone == "" {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_timezone", "请选择有效时区。"))
		return
	}
	if _, err := time.LoadLocation(input.Timezone); err != nil {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_timezone", "请选择有效时区。"))
		return
	}
	user := Current(r.Context())
	user.Timezone = input.Timezone
	if _, err := s.DB.Exec(r.Context(), `UPDATE users SET timezone=$1 WHERE id=$2`, user.Timezone, user.ID); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, user)
}
