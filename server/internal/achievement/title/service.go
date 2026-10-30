package title

import (
	"context"
	"errors"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"skillatlas/internal/achievement/conditions"
	"skillatlas/internal/achievement/state"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
	"skillatlas/internal/skill"
	"time"
)

type Input struct {
	state.Config
	IconKey string `json:"icon_key"`
}
type Title struct {
	Input
	CreatedAt        time.Time              `json:"created_at"`
	UpdatedAt        time.Time              `json:"updated_at"`
	Evaluation       conditions.Evaluation  `json:"evaluation"`
	UnlockedAt       *time.Time             `json:"unlocked_at"`
	EquippedAt       *time.Time             `json:"equipped_at"`
	UnlockedEvidence *conditions.Evaluation `json:"unlocked_evidence"`
}
type Catalog struct {
	Items           []Title `json:"items"`
	EquippedTitleID *string `json:"equipped_title_id"`
}
type Service struct{ DB *pgxpool.Pool }

func (s *Service) Register(mux *http.ServeMux, identity *auth.Service) {
	for route, handler := range map[string]http.HandlerFunc{"GET /v1/titles": s.list, "POST /v1/titles": s.create, "PATCH /v1/titles/{id}": s.edit, "POST /v1/titles/{id}/equip": s.equip, "POST /v1/titles/unequip": s.unequip} {
		mux.HandleFunc(route, identity.Require(handler))
	}
}
func ByID(ctx context.Context, q skill.Queryer, user, id string) (Title, error) {
	var v Title
	err := q.QueryRow(ctx, `SELECT t.id::text,t.name,t.description,t.icon_key,t.conditions_json,t.version,t.created_at,t.updated_at,u.unlocked_at,u.equipped_at,u.evidence_snapshot FROM titles t LEFT JOIN user_titles u ON u.title_id=t.id AND u.user_id=t.user_id WHERE t.user_id=$1 AND t.id=$2`, user, id).Scan(&v.ID, &v.Name, &v.Description, &v.IconKey, &v.Conditions, &v.Version, &v.CreatedAt, &v.UpdatedAt, &v.UnlockedAt, &v.EquippedAt, &v.UnlockedEvidence)
	if err != nil {
		return v, err
	}
	v.Evaluation, err = state.Evaluate(ctx, q, user, v.Conditions)
	return v, err
}
func catalog(ctx context.Context, q skill.Queryer, user string) (Catalog, error) {
	var ids []string
	v := Catalog{Items: []Title{}}
	if err := q.QueryRow(ctx, `SELECT COALESCE(jsonb_agg(id::text ORDER BY created_at,id),'[]'::jsonb) FROM titles WHERE user_id=$1`, user).Scan(&ids); err != nil {
		return v, err
	}
	for _, id := range ids {
		item, err := ByID(ctx, q, user, id)
		if err != nil {
			return v, err
		}
		v.Items = append(v.Items, item)
		if item.EquippedAt != nil {
			v.EquippedTitleID = &item.ID
		}
	}
	return v, nil
}
func (s *Service) list(w http.ResponseWriter, r *http.Request) {
	tx, err := s.DB.BeginTx(r.Context(), pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	defer tx.Rollback(r.Context())
	v, err := catalog(r.Context(), tx, auth.Current(r.Context()).ID)
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, v)
}
func (s *Service) create(w http.ResponseWriter, r *http.Request) { s.save(w, r, true) }
func (s *Service) edit(w http.ResponseWriter, r *http.Request)   { s.save(w, r, false) }
func (s *Service) save(w http.ResponseWriter, r *http.Request, create bool) {
	var input Input
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if !create {
		if input.ID != "" && input.ID != r.PathValue("id") {
			apiutil.WriteError(w, apiutil.Fail(400, "id_mismatch", "路径和称号标识不同。"))
			return
		}
		input.ID = r.PathValue("id")
	}
	if input.IconKey == "" {
		input.IconKey = "star"
	}
	if err := input.Config.Validate(create, input.IconKey); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	status := 200
	if create {
		status = 201
	}
	domain.Mutate(w, r, s.DB, status, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		hash := state.Hash(input)
		kind := "title.updated"
		summary := "更新称号"
		if create {
			if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "title:"+input.ID); err != nil {
				return nil, err
			}
			var owner, original string
			err := tx.QueryRow(ctx, `SELECT user_id::text,create_hash FROM titles WHERE id=$1`, input.ID).Scan(&owner, &original)
			if err == nil {
				if owner != user.ID {
					return nil, apiutil.NotFound()
				}
				if original != hash {
					return nil, apiutil.Fail(409, "id_conflict", "相同称号标识的内容不同。")
				}
				return ByID(ctx, tx, user.ID, input.ID)
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return nil, err
			}
			kind = "title.created"
			summary = "创建称号"
		} else {
			old, err := ByID(ctx, tx, user.ID, input.ID)
			if err != nil {
				return nil, err
			}
			if old.Version != input.Version {
				return nil, apiutil.Fail(409, "version_conflict", "称号配置已变化，请刷新。")
			}
		}
		if err := state.ValidateReferences(ctx, tx, user.ID, input.Conditions); err != nil {
			return nil, err
		}
		var err error
		if create {
			_, err = tx.Exec(ctx, `INSERT INTO titles(id,user_id,name,description,icon_key,conditions_json,create_hash) VALUES($1,$2,$3,$4,$5,$6,$7)`, input.ID, user.ID, input.Name, input.Description, input.IconKey, input.Conditions, hash)
		} else {
			_, err = tx.Exec(ctx, `UPDATE titles SET name=$1,description=$2,icon_key=$3,conditions_json=$4,version=version+1,updated_at=now() WHERE id=$5 AND user_id=$6`, input.Name, input.Description, input.IconKey, input.Conditions, input.ID, user.ID)
		}
		if err != nil {
			return nil, err
		}
		if err = state.RetainReferences(ctx, tx, user.ID, "title", input.ID, input.Conditions); err != nil {
			return nil, err
		}
		cause := fmt.Sprintf("title:%s:v%d", input.ID, input.Version+1)
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, kind, "title", input.ID, cause, summary)); err != nil {
			return nil, err
		}
		if err = state.ReconcileTitles(ctx, tx, user.ID, cause); err != nil {
			return nil, err
		}
		return ByID(ctx, tx, user.ID, input.ID)
	})
}
