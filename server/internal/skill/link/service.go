package link

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
	"skillatlas/internal/skill"
)

type Service struct{ DB *pgxpool.Pool }

func (s *Service) Register(mux *http.ServeMux, identity *auth.Service) {
	for route, handler := range map[string]http.HandlerFunc{"GET /v1/skill-links": s.list, "POST /v1/skill-links": s.create, "PATCH /v1/skill-links/{id}": s.edit, "DELETE /v1/skill-links/{id}": s.remove} {
		mux.HandleFunc(route, identity.Require(handler))
	}
}

const columns = `l.id::text,l.from_skill_id::text,l.to_skill_id::text,l.link_type,l.required_level,l.version,l.created_at,l.deleted_at`

func scan(row pgx.Row) (Link, error) {
	var v Link
	err := row.Scan(&v.ID, &v.FromSkillID, &v.ToSkillID, &v.LinkType, &v.RequiredLevel, &v.Version, &v.CreatedAt, &v.DeletedAt)
	return v, err
}
func byID(ctx context.Context, q skill.Queryer, user, id string) (Link, error) {
	return scan(q.QueryRow(ctx, "SELECT "+columns+" FROM skill_links l WHERE l.user_id=$1 AND l.id=$2", user, id))
}
func (s *Service) list(w http.ResponseWriter, r *http.Request) {
	skillID, treeID := r.URL.Query().Get("skill_id"), r.URL.Query().Get("tree_id")
	if skillID != "" && !apiutil.ValidID(skillID) || treeID != "" && !apiutil.ValidID(treeID) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_filter", "技能或树筛选无效。"))
		return
	}
	rows, err := s.DB.Query(r.Context(), "SELECT "+columns+` FROM skill_links l JOIN skills a ON a.id=l.from_skill_id JOIN skills b ON b.id=l.to_skill_id WHERE l.user_id=$1 AND l.deleted_at IS NULL AND ($2='' OR l.from_skill_id::text=$2 OR l.to_skill_id::text=$2) AND ($3='' OR a.tree_id::text=$3 OR b.tree_id::text=$3) ORDER BY l.created_at,l.id`, auth.Current(r.Context()).ID, skillID, treeID)
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	defer rows.Close()
	items := []Link{}
	for rows.Next() {
		v, err := scan(rows)
		if err != nil {
			apiutil.WriteError(w, err)
			return
		}
		items = append(items, v)
	}
	if err = rows.Err(); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, items)
}
func (s *Service) create(w http.ResponseWriter, r *http.Request) {
	var input Input
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if err := input.Validate(); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	domain.Mutate(w, r, s.DB, 201, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "link:"+input.ID); err != nil {
			return nil, err
		}
		data, _ := json.Marshal(input)
		digest := sha256.Sum256(data)
		hash := hex.EncodeToString(digest[:])
		var owner, original string
		err := tx.QueryRow(ctx, `SELECT user_id::text,create_hash FROM skill_links WHERE id=$1`, input.ID).Scan(&owner, &original)
		if err == nil {
			if owner != user.ID {
				return nil, apiutil.NotFound()
			}
			if hash != original {
				return nil, apiutil.Fail(409, "id_conflict", "相同关系标识的内容不同。")
			}
			return byID(ctx, tx, user.ID, input.ID)
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
		for _, id := range []string{input.FromSkillID, input.ToSkillID} {
			if _, err = skill.Available(ctx, tx, user.ID, id); err != nil {
				return nil, err
			}
		}
		if input.LinkType == "prerequisite" {
			var cyclic bool
			err = tx.QueryRow(ctx, `WITH RECURSIVE reachable(id) AS (SELECT $1::uuid UNION SELECT l.to_skill_id FROM skill_links l JOIN reachable p ON l.from_skill_id=p.id WHERE l.user_id=$3 AND l.link_type='prerequisite' AND l.deleted_at IS NULL) SELECT EXISTS(SELECT 1 FROM reachable WHERE id=$2)`, input.ToSkillID, input.FromSkillID, user.ID).Scan(&cyclic)
			if err != nil {
				return nil, err
			}
			if cyclic {
				return nil, apiutil.Fail(409, "prerequisite_cycle", "这条前置关系会形成循环。")
			}
		}
		if _, err = tx.Exec(ctx, `INSERT INTO skill_links(id,user_id,from_skill_id,to_skill_id,link_type,required_level,create_hash) VALUES($1,$2,$3,$4,$5,$6,$7)`, input.ID, user.ID, input.FromSkillID, input.ToSkillID, input.LinkType, input.RequiredLevel, hash); err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "link.created", "skill_link", input.ID, "link:"+input.ID+":created", "创建技能关系", input.FromSkillID, input.ToSkillID)); err != nil {
			return nil, err
		}
		return byID(ctx, tx, user.ID, input.ID)
	})
}
func (s *Service) edit(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var input struct {
		Version       int   `json:"version"`
		RequiredLevel int64 `json:"required_level"`
	}
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if !apiutil.ValidID(id) || input.Version < 1 || input.RequiredLevel < 1 || input.RequiredLevel > 1000000 {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_link", "关系版本或等级无效。"))
		return
	}
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		old, err := byID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		if old.DeletedAt != nil {
			return nil, apiutil.NotFound()
		}
		if old.LinkType != "prerequisite" {
			return nil, apiutil.Fail(409, "invalid_reference", "普通关联不设置前置等级。")
		}
		if old.Version != input.Version {
			return nil, apiutil.Fail(409, "version_conflict", "关系已变化，请刷新后重试。")
		}
		if _, err = tx.Exec(ctx, `UPDATE skill_links SET required_level=$1,version=version+1 WHERE id=$2 AND user_id=$3`, input.RequiredLevel, id, user.ID); err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "link.updated", "skill_link", id, fmt.Sprintf("link:%s:v%d", id, old.Version+1), "更新技能前置等级", old.FromSkillID, old.ToSkillID)); err != nil {
			return nil, err
		}
		return byID(ctx, tx, user.ID, id)
	})
}
func (s *Service) remove(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !apiutil.ValidID(id) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "关系标识无效。"))
		return
	}
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		old, err := byID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		result := map[string]bool{"deleted": true}
		if old.DeletedAt != nil {
			return result, nil
		}
		if _, err = tx.Exec(ctx, `UPDATE skill_links SET deleted_at=now(),version=version+1 WHERE id=$1 AND user_id=$2`, id, user.ID); err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "link.deleted", "skill_link", id, "link:"+id+":deleted", "移除技能关系", old.FromSkillID, old.ToSkillID)); err != nil {
			return nil, err
		}
		return result, nil
	})
}
