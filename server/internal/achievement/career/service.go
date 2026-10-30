package career

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
	BadgeKey       string  `json:"badge_key"`
	ParentCareerID *string `json:"parent_career_id"`
	SortOrder      int     `json:"sort_order"`
}
type Career struct {
	Input
	CreatedAt     time.Time             `json:"created_at"`
	UpdatedAt     time.Time             `json:"updated_at"`
	Evaluation    conditions.Evaluation `json:"evaluation"`
	ParentReached bool                  `json:"parent_reached"`
}
type Transition struct {
	ID               string                `json:"id"`
	FromCareerID     *string               `json:"from_career_id"`
	ToCareerID       string                `json:"to_career_id"`
	ConfirmedAt      time.Time             `json:"confirmed_at"`
	EvidenceSnapshot conditions.Evaluation `json:"evidence_snapshot"`
}
type Catalog struct {
	Items           []Career     `json:"items"`
	History         []Transition `json:"history"`
	CurrentCareerID *string      `json:"current_career_id"`
}
type Service struct{ DB *pgxpool.Pool }

func (s *Service) Register(mux *http.ServeMux, identity *auth.Service) {
	for route, handler := range map[string]http.HandlerFunc{"GET /v1/career-nodes": s.list, "POST /v1/career-nodes": s.create, "PATCH /v1/career-nodes/{id}": s.edit, "POST /v1/career-nodes/{id}/transition": s.transition} {
		mux.HandleFunc(route, identity.Require(handler))
	}
}
func ByID(ctx context.Context, q skill.Queryer, user, id string) (Career, error) {
	var v Career
	err := q.QueryRow(ctx, `SELECT id::text,name,description,badge_key,parent_career_id::text,sort_order,conditions_json,version,created_at,updated_at FROM career_nodes WHERE user_id=$1 AND id=$2`, user, id).Scan(&v.ID, &v.Name, &v.Description, &v.BadgeKey, &v.ParentCareerID, &v.SortOrder, &v.Conditions, &v.Version, &v.CreatedAt, &v.UpdatedAt)
	if err != nil {
		return v, err
	}
	v.Evaluation, err = state.Evaluate(ctx, q, user, v.Conditions)
	if err != nil {
		return v, err
	}
	v.ParentReached = v.ParentCareerID == nil
	if v.ParentCareerID != nil {
		err = q.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM career_transitions WHERE user_id=$1 AND to_career_id=$2)`, user, *v.ParentCareerID).Scan(&v.ParentReached)
	}
	return v, err
}
func catalog(ctx context.Context, q skill.Queryer, user string) (Catalog, error) {
	v := Catalog{Items: []Career{}, History: []Transition{}}
	var ids []string
	if err := q.QueryRow(ctx, `SELECT COALESCE(jsonb_agg(id::text ORDER BY sort_order,created_at,id),'[]'::jsonb) FROM career_nodes WHERE user_id=$1`, user).Scan(&ids); err != nil {
		return v, err
	}
	for _, id := range ids {
		item, err := ByID(ctx, q, user, id)
		if err != nil {
			return v, err
		}
		v.Items = append(v.Items, item)
	}
	if err := q.QueryRow(ctx, `SELECT (SELECT current_career_id::text FROM achievement_profiles WHERE user_id=$1),COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'from_career_id',from_career_id,'to_career_id',to_career_id,'confirmed_at',confirmed_at,'evidence_snapshot',evidence_snapshot) ORDER BY confirmed_at DESC,id DESC) FROM career_transitions WHERE user_id=$1),'[]'::jsonb)`, user).Scan(&v.CurrentCareerID, &v.History); err != nil {
		return v, err
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
			apiutil.WriteError(w, apiutil.Fail(400, "id_mismatch", "路径和职业标识不同。"))
			return
		}
		input.ID = r.PathValue("id")
	}
	if input.BadgeKey == "" {
		input.BadgeKey = "compass"
	}
	if err := input.Config.Validate(create, input.BadgeKey); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if input.ParentCareerID != nil && (!apiutil.ValidID(*input.ParentCareerID) || *input.ParentCareerID == input.ID) || input.SortOrder < -1000000 || input.SortOrder > 1000000 {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_career", "父级或排序无效。"))
		return
	}
	status := 200
	if create {
		status = 201
	}
	domain.Mutate(w, r, s.DB, status, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		hash := state.Hash(input)
		kind := "career.updated"
		summary := "更新职业阶段"
		if create {
			if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "career:"+input.ID); err != nil {
				return nil, err
			}
			var owner, original string
			err := tx.QueryRow(ctx, `SELECT user_id::text,create_hash FROM career_nodes WHERE id=$1`, input.ID).Scan(&owner, &original)
			if err == nil {
				if owner != user.ID {
					return nil, apiutil.NotFound()
				}
				if original != hash {
					return nil, apiutil.Fail(409, "id_conflict", "相同职业标识的内容不同。")
				}
				return ByID(ctx, tx, user.ID, input.ID)
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return nil, err
			}
			kind = "career.created"
			summary = "创建职业阶段"
		} else {
			old, err := ByID(ctx, tx, user.ID, input.ID)
			if err != nil {
				return nil, err
			}
			if old.Version != input.Version {
				return nil, apiutil.Fail(409, "version_conflict", "职业配置已变化，请刷新。")
			}
		}
		if input.ParentCareerID != nil {
			if _, err := ByID(ctx, tx, user.ID, *input.ParentCareerID); err != nil {
				return nil, err
			}
			var cyclic bool
			if err := tx.QueryRow(ctx, `WITH RECURSIVE parents(id,parent_career_id) AS (SELECT id,parent_career_id FROM career_nodes WHERE id=$1 AND user_id=$3 UNION SELECT n.id,n.parent_career_id FROM career_nodes n JOIN parents p ON n.id=p.parent_career_id WHERE n.user_id=$3) SELECT EXISTS(SELECT 1 FROM parents WHERE id=$2)`, *input.ParentCareerID, input.ID, user.ID).Scan(&cyclic); err != nil {
				return nil, err
			}
			if cyclic {
				return nil, apiutil.Fail(409, "career_cycle", "职业阶段不能形成循环。")
			}
		}
		if err := state.ValidateReferences(ctx, tx, user.ID, input.Conditions); err != nil {
			return nil, err
		}
		var err error
		if create {
			_, err = tx.Exec(ctx, `INSERT INTO career_nodes(id,user_id,name,description,badge_key,parent_career_id,sort_order,conditions_json,create_hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, input.ID, user.ID, input.Name, input.Description, input.BadgeKey, input.ParentCareerID, input.SortOrder, input.Conditions, hash)
		} else {
			_, err = tx.Exec(ctx, `UPDATE career_nodes SET name=$1,description=$2,badge_key=$3,parent_career_id=$4,sort_order=$5,conditions_json=$6,version=version+1,updated_at=now() WHERE id=$7 AND user_id=$8`, input.Name, input.Description, input.BadgeKey, input.ParentCareerID, input.SortOrder, input.Conditions, input.ID, user.ID)
		}
		if err != nil {
			return nil, err
		}
		if err = state.RetainReferences(ctx, tx, user.ID, "career", input.ID, input.Conditions); err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, kind, "career", input.ID, fmt.Sprintf("career:%s:v%d", input.ID, input.Version+1), summary)); err != nil {
			return nil, err
		}
		return ByID(ctx, tx, user.ID, input.ID)
	})
}
