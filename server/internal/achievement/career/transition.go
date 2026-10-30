package career

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5"
	"net/http"
	"skillatlas/internal/achievement/state"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
)

type TransitionInput struct {
	ID           string  `json:"id"`
	Version      int     `json:"version"`
	FromCareerID *string `json:"from_career_id"`
}

func (s *Service) transition(w http.ResponseWriter, r *http.Request) {
	var input TransitionInput
	id := r.PathValue("id")
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if !apiutil.ValidID(input.ID) || !apiutil.ValidID(id) || input.Version < 1 || (input.FromCareerID != nil && !apiutil.ValidID(*input.FromCareerID)) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_transition", "转职标识、版本或当前职业无效。"))
		return
	}
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		hash := state.Hash(struct {
			Kind, Target string
			Input        TransitionInput
		}{"transition", id, input})
		if result, exists, err := state.Replay(ctx, tx, user.ID, input.ID, hash); err != nil {
			return nil, err
		} else if exists {
			return result, nil
		}
		item, err := ByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		if item.Version != input.Version {
			return nil, apiutil.Fail(409, "version_conflict", "职业条件已变化，请刷新后确认。")
		}
		if !item.Evaluation.Eligible || !item.ParentReached {
			return nil, apiutil.Fail(409, "conditions_unmet", "职业条件或前一阶段尚未满足。")
		}
		var current *string
		if err = tx.QueryRow(ctx, `SELECT (SELECT current_career_id::text FROM achievement_profiles WHERE user_id=$1)`, user.ID).Scan(&current); err != nil {
			return nil, err
		}
		if (current == nil) != (input.FromCareerID == nil) || (current != nil && *current != *input.FromCareerID) {
			return nil, apiutil.Fail(409, "career_changed", "当前职业已变化，请刷新后确认。")
		}
		if current != nil && *current == id {
			return nil, apiutil.Fail(409, "already_current", "这已经是当前职业。")
		}
		if _, err = tx.Exec(ctx, `INSERT INTO career_transitions(id,user_id,from_career_id,to_career_id,conditions_snapshot,evidence_snapshot) VALUES($1,$2,$3,$4,$5,$6)`, input.ID, user.ID, current, id, item.Conditions, item.Evaluation); err != nil {
			return nil, err
		}
		if _, err = tx.Exec(ctx, `INSERT INTO achievement_profiles(user_id,current_career_id) VALUES($1,$2) ON CONFLICT(user_id) DO UPDATE SET current_career_id=EXCLUDED.current_career_id`, user.ID, id); err != nil {
			return nil, err
		}
		event := activity.ServerEvent(user.ID, "career.transitioned", "career", id, "transition:"+input.ID, "确认职业转职")
		event.Metadata, _ = json.Marshal(map[string]any{"transition_id": input.ID, "from_career_id": current, "evidence": item.Evaluation})
		if err = activity.Append(ctx, tx, event); err != nil {
			return nil, err
		}
		result, err := catalog(ctx, tx, user.ID)
		if err != nil {
			return nil, err
		}
		if err = state.SaveCommand(ctx, tx, user.ID, input.ID, "transition", &id, hash, result); err != nil {
			return nil, err
		}
		return result, nil
	})
}
