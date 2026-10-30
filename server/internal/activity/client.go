package activity

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
)

type ClientInput struct {
	ID               string    `json:"id"`
	Type             string    `json:"type"`
	EntityID         string    `json:"entity_id"`
	SkillID          string    `json:"skill_id"`
	TaskID           *string   `json:"task_id"`
	OccurredAt       time.Time `json:"occurred_at"`
	Mode             string    `json:"mode"`
	EffectiveSeconds int64     `json:"effective_seconds"`
}

func (v *ClientInput) Validate() error {
	if !apiutil.ValidID(v.ID) || !apiutil.ValidID(v.EntityID) || !apiutil.ValidID(v.SkillID) || (v.TaskID != nil && !apiutil.ValidID(*v.TaskID)) || v.OccurredAt.IsZero() || v.EffectiveSeconds < 0 || v.EffectiveSeconds > 2678400 {
		return apiutil.Fail(400, "invalid_event", "事件标识、时间或有效时长无效。")
	}
	switch v.Type {
	case "focus.started", "focus.paused", "focus.resumed", "focus.ended":
	default:
		return apiutil.Fail(400, "invalid_producer", "客户端只能上报专注生命周期事件。")
	}
	switch v.Mode {
	case "count_up", "countdown", "pomodoro":
	default:
		return apiutil.Fail(400, "invalid_mode", "事件计时模式无效。")
	}
	v.OccurredAt = v.OccurredAt.UTC().Truncate(time.Microsecond)
	return nil
}

func (s *Service) upload(w http.ResponseWriter, r *http.Request) {
	var input ClientInput
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if err := input.Validate(); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	domain.Mutate(w, r, s.DB, 201, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		for _, key := range []string{"focus:" + input.EntityID, "event:" + input.ID} {
			if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, key); err != nil {
				return nil, err
			}
		}
		var existing Event
		err := tx.QueryRow(ctx, `SELECT id::text,user_id::text,type,producer,entity_type,entity_id::text,summary,skill_ids::text[],metadata,occurred_at,created_at FROM activity_events WHERE id=$1`, input.ID).Scan(&existing.ID, &existing.UserID, &existing.Type, &existing.Producer, &existing.EntityType, &existing.EntityID, &existing.Summary, &existing.SkillIDs, &existing.Metadata, &existing.OccurredAt, &existing.CreatedAt)
		data, _ := json.Marshal(input)
		if err == nil {
			if existing.UserID != user.ID {
				return nil, apiutil.NotFound()
			}
			var original ClientInput
			if existing.Producer != "client" || json.Unmarshal(existing.Metadata, &original) != nil {
				return nil, apiutil.Fail(409, "id_conflict", "该事件标识已被使用。")
			}
			originalData, _ := json.Marshal(original)
			if string(originalData) != string(data) {
				return nil, apiutil.Fail(409, "id_conflict", "同一事件标识对应的内容不同。")
			}
			return existing, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
		var owned bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM skills WHERE id=$1 AND user_id=$2)`, input.SkillID, user.ID).Scan(&owned); err != nil {
			return nil, err
		}
		if !owned {
			return nil, apiutil.NotFound()
		}
		if input.TaskID != nil {
			if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM tasks WHERE id=$1 AND user_id=$2)`, *input.TaskID, user.ID).Scan(&owned); err != nil {
				return nil, err
			}
			if !owned {
				return nil, apiutil.NotFound()
			}
		}
		var foreign, inconsistent bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM focus_sessions WHERE id=$1 AND user_id<>$2) OR EXISTS(SELECT 1 FROM activity_events WHERE entity_type='focus_session' AND entity_id=$1 AND user_id<>$2)`, input.EntityID, user.ID).Scan(&foreign); err != nil {
			return nil, err
		}
		if foreign {
			return nil, apiutil.NotFound()
		}
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM focus_sessions WHERE id=$1 AND (skill_id<>$2 OR mode<>$3)) OR EXISTS(SELECT 1 FROM activity_events WHERE entity_type='focus_session' AND entity_id=$1 AND producer='client' AND (NOT skill_ids @> ARRAY[$2]::uuid[] OR metadata->>'mode'<>$3))`, input.EntityID, input.SkillID, input.Mode).Scan(&inconsistent); err != nil {
			return nil, err
		}
		if inconsistent {
			return nil, apiutil.Fail(409, "focus_conflict", "同一会话的技能或计时模式不一致。")
		}
		summaries := map[string]string{"focus.started": "开始专注", "focus.paused": "暂停专注", "focus.resumed": "继续专注", "focus.ended": "结束专注"}
		event := Event{ID: input.ID, UserID: user.ID, Type: input.Type, Producer: "client", EntityType: "focus_session", EntityID: input.EntityID, SourceKey: "client:" + input.ID, Summary: summaries[input.Type], SkillIDs: []string{input.SkillID}, Metadata: data, OccurredAt: input.OccurredAt}
		if err = Append(ctx, tx, event); err != nil {
			return nil, err
		}
		if err = tx.QueryRow(ctx, `SELECT created_at FROM activity_events WHERE id=$1`, input.ID).Scan(&event.CreatedAt); err != nil {
			return nil, err
		}
		return event, nil
	})
}
