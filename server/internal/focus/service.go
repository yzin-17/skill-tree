package focus

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"math"
	"net/http"
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
	mux.HandleFunc("POST /v1/focus-sessions", identity.Require(s.upload))
	mux.HandleFunc("GET /v1/focus-sessions", identity.Require(s.list))
	mux.HandleFunc("GET /v1/focus-sessions/{id}", identity.Require(s.get))
	mux.HandleFunc("PATCH /v1/focus-sessions/{id}/task", identity.Require(s.bind))
}

const columns = `id::text,skill_id::text,task_id::text,mode,target_seconds,effective_seconds,started_at,ended_at,note,source,pomodoro_rounds,version,created_at,invalidated_at,clock_adjusted`

func scan(row pgx.Row) (Session, error) {
	var item Session
	err := row.Scan(&item.ID, &item.SkillID, &item.TaskID, &item.Mode, &item.TargetSeconds, &item.EffectiveSeconds, &item.StartedAt, &item.EndedAt, &item.Note, &item.Source, &item.PomodoroRounds, &item.Version, &item.CreatedAt, &item.InvalidatedAt, &item.ClockAdjusted)
	return item, err
}
func ByID(ctx context.Context, q skill.Queryer, user, id string) (Session, error) {
	return scan(q.QueryRow(ctx, "SELECT "+columns+" FROM focus_sessions WHERE user_id=$1 AND id=$2", user, id))
}
func (s *Service) upload(w http.ResponseWriter, r *http.Request) {
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
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "focus:"+input.ID); err != nil {
			return nil, err
		}
		data, _ := json.Marshal(input)
		digest := sha256.Sum256(data)
		fingerprint := hex.EncodeToString(digest[:])
		var owner, original string
		var awarded int64
		var settled growth.Progress
		err := tx.QueryRow(ctx, `SELECT user_id::text,create_hash,awarded_xp,settled_progress FROM focus_sessions WHERE id=$1`, input.ID).Scan(&owner, &original, &awarded, &settled)
		if err == nil {
			if owner != user.ID {
				return nil, apiutil.NotFound()
			}
			if original != fingerprint {
				return nil, apiutil.Fail(409, "id_conflict", "同一会话标识对应的内容不同。")
			}
			session, err := ByID(ctx, tx, user.ID, input.ID)
			return Settlement{Session: session, AwardedXP: awarded, SettledProgress: settled}, err
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
		var foreign bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM activity_events WHERE entity_type='focus_session' AND entity_id=$1 AND user_id<>$2)`, input.ID, user.ID).Scan(&foreign); err != nil {
			return nil, err
		}
		if foreign {
			return nil, apiutil.NotFound()
		}
		var inconsistent bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM activity_events WHERE entity_type='focus_session' AND entity_id=$1 AND producer='client' AND (NOT skill_ids @> ARRAY[$2]::uuid[] OR metadata->>'mode'<>$3))`, input.ID, input.SkillID, input.Mode).Scan(&inconsistent); err != nil {
			return nil, err
		}
		if inconsistent {
			return nil, apiutil.Fail(409, "focus_conflict", "会话与已上报事件的技能或模式不一致。")
		}
		if _, err = skill.ByID(ctx, tx, user.ID, input.SkillID); err != nil {
			return nil, err
		}
		if input.TaskID != nil {
			if _, err = task.ByID(ctx, tx, user.ID, *input.TaskID); err != nil {
				return nil, err
			}
		}
		before, err := growth.Read(ctx, tx, user.ID, input.SkillID)
		if err != nil {
			return nil, err
		}
		if before.TotalFocusSeconds > math.MaxInt64-input.EffectiveSeconds {
			return nil, apiutil.Fail(400, "duration_overflow", "累计时长超出可保存范围。")
		}
		awarded = growth.FocusXP(before.TotalFocusSeconds, input.EffectiveSeconds)
		adjusted := input.EndedAt.Before(input.StartedAt) || float64(input.EffectiveSeconds) > input.EndedAt.Sub(input.StartedAt).Seconds()+1
		_, err = tx.Exec(ctx, `INSERT INTO focus_sessions(id,user_id,skill_id,task_id,mode,target_seconds,effective_seconds,started_at,ended_at,note,source,pomodoro_rounds,clock_adjusted,create_hash,awarded_xp) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)`, input.ID, user.ID, input.SkillID, input.TaskID, input.Mode, input.TargetSeconds, input.EffectiveSeconds, input.StartedAt, input.EndedAt, input.Note, input.Source, input.PomodoroRounds, adjusted, fingerprint, awarded)
		if err != nil {
			return nil, err
		}
		if _, err = growth.Record(ctx, tx, user.ID, input.SkillID, "focus_accrual", input.ID, awarded, "专注时间经验", nil); err != nil {
			return nil, err
		}
		after, err := growth.Read(ctx, tx, user.ID, input.SkillID)
		if err != nil {
			return nil, err
		}
		if _, err = tx.Exec(ctx, `UPDATE focus_sessions SET settled_progress=$1 WHERE id=$2`, after, input.ID); err != nil {
			return nil, err
		}
		event := activity.ServerEvent(user.ID, "focus.recorded", "focus_session", input.ID, "focus:"+input.ID+":recorded", "记录专注", input.SkillID)
		event.OccurredAt = input.EndedAt
		event.Metadata, _ = json.Marshal(map[string]any{"source": input.Source, "effective_seconds": input.EffectiveSeconds, "awarded_xp": awarded, "task_id": input.TaskID, "clock_adjusted": adjusted})
		if err = activity.Append(ctx, tx, event); err != nil {
			return nil, err
		}
		if err = growth.LevelUp(ctx, tx, user.ID, input.ID, before, after); err != nil {
			return nil, err
		}
		if err = state.ReconcileTitles(ctx, tx, user.ID, input.ID); err != nil {
			return nil, err
		}
		session, err := ByID(ctx, tx, user.ID, input.ID)
		return Settlement{Session: session, AwardedXP: awarded, SettledProgress: after}, err
	})
}
