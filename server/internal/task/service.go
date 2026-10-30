package task

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
	for path, handler := range map[string]http.HandlerFunc{"GET /v1/tasks": s.list, "POST /v1/tasks": s.create, "GET /v1/tasks/{id}": s.get, "PATCH /v1/tasks/{id}": s.edit} {
		mux.HandleFunc(path, identity.Require(handler))
	}
}

const columns = `t.id::text,t.title,t.description,t.success_criteria,t.status,t.due_at,t.pinned,t.version,t.current_attempt_no,t.created_at,t.updated_at,COALESCE((SELECT jsonb_agg(jsonb_build_object('skill_id',ts.skill_id,'reward_levels',ts.reward_levels) ORDER BY ts.skill_id) FROM task_skills ts WHERE ts.task_id=t.id),'[]'::jsonb),COALESCE((SELECT sum(effective_seconds) FROM focus_sessions f WHERE f.task_id=t.id AND f.invalidated_at IS NULL),0),(SELECT count(*) FROM focus_sessions f WHERE f.task_id=t.id AND f.invalidated_at IS NULL),(SELECT count(*) FROM task_attempts a WHERE a.task_id=t.id AND a.reversed_at IS NULL AND a.result='success'),(SELECT count(*) FROM task_attempts a WHERE a.task_id=t.id AND a.reversed_at IS NULL AND a.result='failed'),(SELECT count(*) FROM task_retry_requests rr WHERE rr.task_id=t.id)`

func scan(row pgx.Row) (Task, error) {
	var item Task
	var successes, failures, retries int64
	err := row.Scan(&item.ID, &item.Title, &item.Description, &item.SuccessCriteria, &item.Status, &item.DueAt, &item.Pinned, &item.Version, &item.CurrentAttemptNo, &item.CreatedAt, &item.UpdatedAt, &item.Skills, &item.TotalFocusSeconds, &item.FocusCount, &successes, &failures, &retries)
	item.AttemptSummary = SummarizeAttempts(successes, failures, retries)
	return item, err
}
func ByID(ctx context.Context, q skill.Queryer, user, id string) (Task, error) {
	return scan(q.QueryRow(ctx, "SELECT "+columns+" FROM tasks t WHERE t.user_id=$1 AND t.id=$2", user, id))
}
func readError(w http.ResponseWriter, err error) {
	if errors.Is(err, pgx.ErrNoRows) {
		err = apiutil.NotFound()
	}
	apiutil.WriteError(w, err)
}
func (s *Service) list(w http.ResponseWriter, r *http.Request) {
	status, skillID := r.URL.Query().Get("status"), r.URL.Query().Get("skill_id")
	if status != "" && !ValidStatus(status) || skillID != "" && !apiutil.ValidID(skillID) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_filter", "状态或技能筛选无效。"))
		return
	}
	rows, err := s.DB.Query(r.Context(), "SELECT "+columns+` FROM tasks t WHERE t.user_id=$1 AND ($2='' OR t.status=$2) AND ($3='' OR EXISTS(SELECT 1 FROM task_skills ts WHERE ts.task_id=t.id AND ts.skill_id::text=$3)) ORDER BY t.pinned DESC,t.due_at ASC NULLS LAST,t.created_at DESC,t.id`, auth.Current(r.Context()).ID, status, skillID)
	if err != nil {
		readError(w, err)
		return
	}
	defer rows.Close()
	items := []Task{}
	for rows.Next() {
		item, err := scan(rows)
		if err != nil {
			readError(w, err)
			return
		}
		items = append(items, item)
	}
	if err = rows.Err(); err != nil {
		readError(w, err)
		return
	}
	apiutil.Write(w, 200, items)
}
func (s *Service) get(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !apiutil.ValidID(id) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "任务标识无效。"))
		return
	}
	item, err := ByID(r.Context(), s.DB, auth.Current(r.Context()).ID, id)
	if err != nil {
		readError(w, err)
		return
	}
	apiutil.Write(w, 200, item)
}
func validateSkills(ctx context.Context, tx pgx.Tx, user string, bindings, previous []Binding) error {
	kept := map[string]bool{}
	for _, binding := range previous {
		kept[binding.SkillID] = true
	}
	for _, binding := range bindings {
		var err error
		if kept[binding.SkillID] {
			_, err = skill.ByID(ctx, tx, user, binding.SkillID)
		} else {
			_, err = skill.Available(ctx, tx, user, binding.SkillID)
		}
		if err != nil {
			return err
		}
	}
	return nil
}
func saveBindings(ctx context.Context, tx pgx.Tx, user, id string, bindings []Binding) error {
	if _, err := tx.Exec(ctx, `DELETE FROM task_skills WHERE task_id=$1 AND user_id=$2`, id, user); err != nil {
		return err
	}
	for _, binding := range bindings {
		if _, err := tx.Exec(ctx, `INSERT INTO task_skills(task_id,skill_id,user_id,reward_levels) VALUES($1,$2,$3,$4)`, id, binding.SkillID, user, binding.RewardLevels); err != nil {
			return err
		}
	}
	return nil
}
func skillIDs(bindings []Binding) []string {
	ids := []string{}
	for _, binding := range bindings {
		ids = append(ids, binding.SkillID)
	}
	return ids
}
func (s *Service) create(w http.ResponseWriter, r *http.Request) {
	var input Input
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if err := input.Validate(true); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	domain.Mutate(w, r, s.DB, 201, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		data, _ := json.Marshal(input)
		digest := sha256.Sum256(data)
		fingerprint := hex.EncodeToString(digest[:])
		var owner, original string
		err := tx.QueryRow(ctx, `SELECT user_id::text,create_hash FROM tasks WHERE id=$1`, input.ID).Scan(&owner, &original)
		if err == nil {
			if owner != user.ID {
				return nil, apiutil.NotFound()
			}
			if original != fingerprint {
				return nil, apiutil.Fail(409, "id_conflict", "同一创建标识对应的内容不同。")
			}
			return ByID(ctx, tx, user.ID, input.ID)
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
		if err = validateSkills(ctx, tx, user.ID, input.Skills, nil); err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, `INSERT INTO tasks(id,user_id,title,description,success_criteria,status,due_at,pinned,create_hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, input.ID, user.ID, input.Title, input.Description, input.SuccessCriteria, input.Status, input.DueAt, input.Pinned, fingerprint)
		if err != nil {
			return nil, err
		}
		if err = saveBindings(ctx, tx, user.ID, input.ID, input.Skills); err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "task.created", "task", input.ID, "task:"+input.ID+":created", "创建任务「"+input.Title+"」", skillIDs(input.Skills)...)); err != nil {
			return nil, err
		}
		return ByID(ctx, tx, user.ID, input.ID)
	})
}
func (s *Service) edit(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var input Input
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if input.ID != "" && input.ID != id {
		apiutil.WriteError(w, apiutil.Fail(400, "id_mismatch", "路径与记录标识不同。"))
		return
	}
	input.ID = id
	if err := input.Validate(false); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		existing, err := ByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		if existing.Version != input.Version {
			return nil, apiutil.Fail(409, "version_conflict", "任务已更新，请刷新后重试。")
		}
		if err = ValidateEdit(existing.Status, input.Status); err != nil {
			return nil, err
		}
		if err = validateSkills(ctx, tx, user.ID, input.Skills, existing.Skills); err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, `UPDATE tasks SET title=$1,description=$2,success_criteria=$3,status=$4,due_at=$5,pinned=$6,version=version+1,updated_at=now() WHERE id=$7 AND user_id=$8`, input.Title, input.Description, input.SuccessCriteria, input.Status, input.DueAt, input.Pinned, id, user.ID)
		if err != nil {
			return nil, err
		}
		if err = saveBindings(ctx, tx, user.ID, id, input.Skills); err != nil {
			return nil, err
		}
		kind, summary := "task.updated", "更新任务「"+input.Title+"」"
		if input.Status == "canceled" && existing.Status != "canceled" {
			kind, summary = "task.canceled", "取消任务「"+input.Title+"」"
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, kind, "task", id, fmt.Sprintf("task:%s:v%d", id, input.Version+1), summary, skillIDs(input.Skills)...)); err != nil {
			return nil, err
		}
		return ByID(ctx, tx, user.ID, id)
	})
}
