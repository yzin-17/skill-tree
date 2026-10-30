package attempt

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"skillatlas/internal/achievement/state"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
	"skillatlas/internal/growth"
	"skillatlas/internal/skill"
	"skillatlas/internal/task"
)

type Service struct{ DB *pgxpool.Pool }

func (s *Service) Register(mux *http.ServeMux, identity *auth.Service) {
	mux.HandleFunc("GET /v1/task-retries/{id}", identity.Require(s.retryDetail))
	mux.HandleFunc("POST /v1/tasks/{id}/attempts", identity.Require(s.conclude))
	mux.HandleFunc("GET /v1/tasks/{id}/attempts", identity.Require(s.list))
	mux.HandleFunc("GET /v1/task-attempts/{id}", identity.Require(s.get))
	mux.HandleFunc("POST /v1/tasks/{id}/retry", identity.Require(s.retry))
	mux.HandleFunc("POST /v1/task-attempts/{id}/reverse", identity.Require(s.reverse))
}
func fingerprint(value any) string {
	data, _ := json.Marshal(value)
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
func validPath(w http.ResponseWriter, r *http.Request) bool {
	if !apiutil.ValidID(r.PathValue("id")) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "记录标识无效。"))
		return false
	}
	return true
}

const columns = `a.id::text,a.task_id::text,a.attempt_no,a.result,a.reason,a.concluded_at,a.reversed_at,COALESCE((SELECT jsonb_agg(jsonb_build_object('skill_id',s.skill_id,'reward_levels',s.reward_levels) ORDER BY s.skill_id) FROM task_attempt_skills s WHERE s.attempt_id=a.id),'[]'::jsonb)`

func ByID(ctx context.Context, q skill.Queryer, user, id string) (Attempt, error) {
	var value Attempt
	err := q.QueryRow(ctx, "SELECT "+columns+" FROM task_attempts a WHERE a.user_id=$1 AND a.id=$2", user, id).Scan(&value.ID, &value.TaskID, &value.AttemptNo, &value.Result, &value.Reason, &value.ConcludedAt, &value.ReversedAt, &value.SkillSnapshot)
	return value, err
}
func rewards(ctx context.Context, q skill.Queryer, user, id string) ([]Reward, error) {
	var result []Reward
	err := q.QueryRow(ctx, `SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'attempt_id',attempt_id,'skill_id',skill_id,'reward_levels_snapshot',reward_levels_snapshot,'xp_amount',xp_amount,'growth_event_id',growth_event_id) ORDER BY skill_id),'[]'::jsonb) FROM task_rewards WHERE user_id=$1 AND attempt_id=$2`, user, id).Scan(&result)
	return result, err
}
func (s *Service) conclude(w http.ResponseWriter, r *http.Request) {
	if !validPath(w, r) {
		return
	}
	var input Conclusion
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if err := input.Validate(); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	id := r.PathValue("id")
	domain.Mutate(w, r, s.DB, 201, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "attempt:"+input.ID); err != nil {
			return nil, err
		}
		hash := fingerprint(struct {
			TaskID string
			Input  Conclusion
		}{id, input})
		var owner, original string
		var saved json.RawMessage
		err := tx.QueryRow(ctx, `SELECT user_id::text,request_hash,result_json FROM task_attempts WHERE id=$1`, input.ID).Scan(&owner, &original, &saved)
		if err == nil {
			if owner != user.ID {
				return nil, apiutil.NotFound()
			}
			if original != hash {
				return nil, apiutil.Fail(409, "id_conflict", "相同尝试标识的结算内容不同。")
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
		if current.Status != "todo" && current.Status != "in_progress" {
			return nil, apiutil.Fail(409, "invalid_transition", "当前任务无法结算，请刷新状态。")
		}
		if current.CurrentAttemptNo != input.AttemptNo || current.Version != input.Version {
			return nil, apiutil.Fail(409, "version_conflict", "任务或奖励配置已变化，请刷新后确认。")
		}
		if _, err = tx.Exec(ctx, `INSERT INTO task_attempts(id,user_id,task_id,attempt_no,result,reason,request_hash) VALUES($1,$2,$3,$4,$5,$6,$7)`, input.ID, user.ID, id, input.AttemptNo, input.Result, input.Reason, hash); err != nil {
			return nil, err
		}
		progress := []growth.Progress{}
		ids := []string{}
		for _, binding := range current.Skills {
			ids = append(ids, binding.SkillID)
			if _, err = tx.Exec(ctx, `INSERT INTO task_attempt_skills(attempt_id,user_id,skill_id,reward_levels) VALUES($1,$2,$3,$4)`, input.ID, user.ID, binding.SkillID, binding.RewardLevels); err != nil {
				return nil, err
			}
			if input.Result == "success" {
				before, err := growth.Read(ctx, tx, user.ID, binding.SkillID)
				if err != nil {
					return nil, err
				}
				xp := binding.RewardLevels * 60
				event, err := growth.Record(ctx, tx, user.ID, binding.SkillID, "task_success", input.ID, xp, "任务成功奖励", nil)
				if err != nil {
					return nil, err
				}
				if _, err = tx.Exec(ctx, `INSERT INTO task_rewards(id,user_id,attempt_id,skill_id,reward_levels_snapshot,xp_amount,growth_event_id) VALUES($1,$2,$3,$4,$5,$6,$7)`, apiutil.ID(), user.ID, input.ID, binding.SkillID, binding.RewardLevels, xp, event); err != nil {
					return nil, err
				}
				after, err := growth.Read(ctx, tx, user.ID, binding.SkillID)
				if err != nil {
					return nil, err
				}
				progress = append(progress, after)
				if err = growth.LevelUp(ctx, tx, user.ID, input.ID, before, after); err != nil {
					return nil, err
				}
			}
		}
		if _, err = tx.Exec(ctx, `UPDATE tasks SET status=$1,version=version+1,updated_at=now() WHERE id=$2 AND user_id=$3`, input.Result, id, user.ID); err != nil {
			return nil, err
		}
		summary := "任务成功"
		if input.Result == "failed" {
			summary = "任务失败"
		}
		event := activity.ServerEvent(user.ID, "attempt."+input.Result, "task_attempt", input.ID, "attempt:"+input.ID, summary, ids...)
		event.Metadata, _ = json.Marshal(map[string]any{"task_id": id, "attempt_no": input.AttemptNo, "reason": input.Reason})
		if err = activity.Append(ctx, tx, event); err != nil {
			return nil, err
		}
		item, err := ByID(ctx, tx, user.ID, input.ID)
		if err == nil {
			err = state.ReconcileTitles(ctx, tx, user.ID, input.ID)
		}
		if err != nil {
			return nil, err
		}
		rewardRows, err := rewards(ctx, tx, user.ID, input.ID)
		if err != nil {
			return nil, err
		}
		updated, err := task.ByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		result := Settlement{Detail: Detail{Attempt: item, Rewards: rewardRows}, Task: updated, SettledProgress: progress}
		if _, err = tx.Exec(ctx, `UPDATE task_attempts SET result_json=$1 WHERE id=$2`, result, input.ID); err != nil {
			return nil, err
		}
		return result, nil
	})
}
