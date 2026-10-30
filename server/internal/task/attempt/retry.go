package attempt

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/jackc/pgx/v5"
	"net/http"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
	"skillatlas/internal/task"
)

func (s *Service) retry(w http.ResponseWriter, r *http.Request) {
	if !validPath(w, r) {
		return
	}
	var input RetryInput
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if !apiutil.ValidID(input.ID) || input.AttemptNo < 1 || input.Version < 1 {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_retry", "重试标识、编号或版本无效。"))
		return
	}
	id := r.PathValue("id")
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "retry:"+input.ID); err != nil {
			return nil, err
		}
		hash := fingerprint(struct {
			TaskID string
			Input  RetryInput
		}{id, input})
		var owner, original string
		var saved json.RawMessage
		err := tx.QueryRow(ctx, `SELECT user_id::text,request_hash,result_json FROM task_retry_requests WHERE id=$1`, input.ID).Scan(&owner, &original, &saved)
		if err == nil {
			if owner != user.ID {
				return nil, apiutil.NotFound()
			}
			if original != hash {
				return nil, apiutil.Fail(409, "id_conflict", "相同重试标识的内容不同。")
			}
			return saved, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
		current, err := task.ByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		if current.Status != "failed" {
			return nil, apiutil.Fail(409, "invalid_transition", "只有失败任务可以开启重试。")
		}
		if current.Version != input.Version || current.CurrentAttemptNo != input.AttemptNo {
			return nil, apiutil.Fail(409, "version_conflict", "任务已变化，请刷新后重试。")
		}
		if _, err = tx.Exec(ctx, `INSERT INTO task_retry_requests(id,user_id,task_id,previous_attempt_no,next_attempt_no,request_hash) VALUES($1,$2,$3,$4,$4+1,$5)`, input.ID, user.ID, id, input.AttemptNo, hash); err != nil {
			return nil, err
		}
		if _, err = tx.Exec(ctx, `UPDATE tasks SET status='in_progress',current_attempt_no=current_attempt_no+1,version=version+1,updated_at=now() WHERE id=$1 AND user_id=$2`, id, user.ID); err != nil {
			return nil, err
		}
		ids := []string{}
		for _, binding := range current.Skills {
			ids = append(ids, binding.SkillID)
		}
		event := activity.ServerEvent(user.ID, "task.retried", "task", id, "retry:"+input.ID, "开启新的任务尝试", ids...)
		event.Metadata, _ = json.Marshal(map[string]any{"request_id": input.ID, "previous_attempt_no": input.AttemptNo, "attempt_no": input.AttemptNo + 1})
		if err = activity.Append(ctx, tx, event); err != nil {
			return nil, err
		}
		updated, err := task.ByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		if _, err = tx.Exec(ctx, `UPDATE task_retry_requests SET result_json=$1 WHERE id=$2`, updated, input.ID); err != nil {
			return nil, err
		}
		return updated, nil
	})
}
