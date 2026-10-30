package skill

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
)

type Service struct{ DB *pgxpool.Pool }
type Queryer interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func (s *Service) Register(mux *http.ServeMux, identity *auth.Service) {
	routes := map[string]http.HandlerFunc{
		"GET /v1/skill-trees": s.listTrees, "POST /v1/skill-trees": s.createTree, "GET /v1/skill-trees/{id}": s.getTree, "PATCH /v1/skill-trees/{id}": s.editTree,
		"GET /v1/skills": s.listSkills, "POST /v1/skills": s.createSkill, "GET /v1/skills/{id}": s.getSkill, "PATCH /v1/skills/{id}": s.editSkill, "DELETE /v1/skills/{id}": s.deleteSkill,
	}
	for route, handler := range routes {
		mux.HandleFunc(route, identity.Require(handler))
	}
}
func hash(value any) string {
	data, _ := json.Marshal(value)
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:])
}
func readError(w http.ResponseWriter, err error) {
	if errors.Is(err, pgx.ErrNoRows) {
		err = apiutil.NotFound()
	}
	apiutil.WriteError(w, err)
}
func pathID(w http.ResponseWriter, r *http.Request) (string, bool) {
	id := r.PathValue("id")
	if !apiutil.ValidID(id) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "记录标识无效。"))
		return "", false
	}
	return id, true
}
func versionError() error {
	return apiutil.Fail(409, "version_conflict", "记录已更新，请刷新后重试。")
}
func archiveError() error {
	return apiutil.Fail(409, "archived", "所选技能或技能树已归档，请重新选择。")
}
func replay(ctx context.Context, tx pgx.Tx, table, id, user, digest string) (bool, error) {
	var owner, existing string
	err := tx.QueryRow(ctx, "SELECT user_id::text,create_hash FROM "+table+" WHERE id=$1", id).Scan(&owner, &existing)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if owner != user {
		return false, apiutil.NotFound()
	}
	if existing != digest {
		return false, apiutil.Fail(409, "id_conflict", "同一创建标识对应的内容不同。")
	}
	return true, nil
}
