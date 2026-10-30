package attempt

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/jackc/pgx/v5"
	"net/http"
	"skillatlas/internal/achievement/state"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
	"skillatlas/internal/growth"
	"skillatlas/internal/task"
	"unicode/utf8"
)

func (s *Service) reverse(w http.ResponseWriter, r *http.Request) {
	if !validPath(w, r) {
		return
	}
	var input ReverseInput
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if !apiutil.ValidID(input.ID) || utf8.RuneCountInString(input.Reason) > 4000 {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_reversal", "撤销标识或说明无效。"))
		return
	}
	id := r.PathValue("id")
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "reversal:"+input.ID); err != nil {
			return nil, err
		}
		hash := fingerprint(struct {
			AttemptID string
			Input     ReverseInput
		}{id, input})
		var owner, original string
		var saved json.RawMessage
		err := tx.QueryRow(ctx, `SELECT user_id::text,request_hash,result_json FROM task_reversals WHERE id=$1`, input.ID).Scan(&owner, &original, &saved)
		if err == nil {
			if owner != user.ID {
				return nil, apiutil.NotFound()
			}
			if original != hash {
				return nil, apiutil.Fail(409, "id_conflict", "相同撤销标识的内容不同。")
			}
			return saved, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
		item, err := ByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		current, err := task.ByID(ctx, tx, user.ID, item.TaskID)
		if err != nil {
			return nil, err
		}
		if item.ReversedAt != nil {
			return nil, apiutil.Fail(409, "already_reversed", "这次结算已经撤销。")
		}
		if current.CurrentAttemptNo != item.AttemptNo {
			return nil, apiutil.Fail(409, "later_attempt", "已开启后续尝试，不能撤销这次历史结算。")
		}
		var reversal Reversal
		err = tx.QueryRow(ctx, `INSERT INTO task_reversals(id,user_id,attempt_id,reason,request_hash) VALUES($1,$2,$3,$4,$5) RETURNING id::text,attempt_id::text,reason,created_at`, input.ID, user.ID, id, input.Reason, hash).Scan(&reversal.ID, &reversal.AttemptID, &reversal.Reason, &reversal.CreatedAt)
		if err != nil {
			return nil, err
		}
		rewardRows, err := rewards(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		progress := []growth.Progress{}
		for _, reward := range rewardRows {
			if _, err = growth.Record(ctx, tx, user.ID, reward.SkillID, "reversal", id, -reward.XPAmount, "撤销任务成功奖励", &reward.GrowthEventID); err != nil {
				return nil, err
			}
			p, err := growth.Read(ctx, tx, user.ID, reward.SkillID)
			if err != nil {
				return nil, err
			}
			progress = append(progress, p)
		}
		if _, err = tx.Exec(ctx, `UPDATE task_attempts SET reversed_at=$1 WHERE id=$2 AND user_id=$3`, reversal.CreatedAt, id, user.ID); err != nil {
			return nil, err
		}
		if _, err = tx.Exec(ctx, `UPDATE tasks SET status='in_progress',current_attempt_no=current_attempt_no+1,version=version+1,updated_at=now() WHERE id=$1 AND user_id=$2`, item.TaskID, user.ID); err != nil {
			return nil, err
		}
		ids := []string{}
		for _, binding := range item.SkillSnapshot {
			ids = append(ids, binding.SkillID)
		}
		event := activity.ServerEvent(user.ID, "attempt.reversed", "task_attempt", id, "reversal:"+input.ID, "撤销任务结算", ids...)
		event.Metadata, _ = json.Marshal(map[string]any{"reversal_id": input.ID, "task_id": item.TaskID, "attempt_no": item.AttemptNo, "reason": input.Reason})
		if err = activity.Append(ctx, tx, event); err != nil {
			return nil, err
		}
		item.ReversedAt = &reversal.CreatedAt
		if err = state.ReconcileTitles(ctx, tx, user.ID, input.ID); err != nil {
			return nil, err
		}
		updated, err := task.ByID(ctx, tx, user.ID, item.TaskID)
		if err != nil {
			return nil, err
		}
		result := Settlement{Detail: Detail{Attempt: item, Rewards: rewardRows, Reversal: &reversal}, Task: updated, SettledProgress: progress}
		if _, err = tx.Exec(ctx, `UPDATE task_reversals SET result_json=$1 WHERE id=$2`, result, input.ID); err != nil {
			return nil, err
		}
		return result, nil
	})
}
