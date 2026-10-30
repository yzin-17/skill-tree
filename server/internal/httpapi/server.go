package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"skillatlas/internal/achievement/career"
	"skillatlas/internal/achievement/title"
	"skillatlas/internal/activity"
	"skillatlas/internal/auth"
	"skillatlas/internal/export"
	"skillatlas/internal/focus"
	"skillatlas/internal/growth"
	"skillatlas/internal/skill"
	"skillatlas/internal/skill/link"
	"skillatlas/internal/stats"
	"skillatlas/internal/task"
	"skillatlas/internal/task/attempt"
)

const Version = "0.1.0"

type Server struct {
	DB   *pgxpool.Pool
	Mux  *http.ServeMux
	Auth *auth.Service
}

func New(pool *pgxpool.Pool) *Server {
	s := &Server{DB: pool, Mux: http.NewServeMux()}
	s.Auth = auth.New(pool)
	s.Auth.Register(s.Mux)
	(&activity.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&skill.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&link.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&task.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&attempt.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&focus.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&growth.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&career.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&title.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&stats.Service{DB: pool}).Register(s.Mux, s.Auth)
	(&export.Service{DB: pool}).Register(s.Mux, s.Auth)
	s.Mux.HandleFunc("GET /health", s.health)
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	s.Mux.ServeHTTP(w, r)
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if s.DB.Ping(ctx) != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": "database_unavailable", "message": "数据库暂不可用"}})
		return
	}
	json.NewEncoder(w).Encode(map[string]any{"data": map[string]string{"service": "Skill Atlas", "status": "ok", "version": Version, "database": "ready"}})
}
