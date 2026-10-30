package title

import (
	"context"
	"github.com/jackc/pgx/v5"
	"net/http"
	"skillatlas/internal/achievement/state"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
)

type EquipInput struct {
	ID      string `json:"id"`
	Version int    `json:"version"`
}
type UnequipInput struct {
	ID string `json:"id"`
}

func (s *Service) equip(w http.ResponseWriter, r *http.Request) {
	var input EquipInput
	id := r.PathValue("id")
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if !apiutil.ValidID(id) || !apiutil.ValidID(input.ID) || input.Version < 1 {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_equip", "佩戴标识或版本无效。"))
		return
	}
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		hash := state.Hash(struct {
			Kind, Target string
			Input        EquipInput
		}{"equip", id, input})
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
			return nil, apiutil.Fail(409, "version_conflict", "称号配置已变化，请刷新后确认。")
		}
		if !item.Evaluation.Eligible {
			return nil, apiutil.Fail(409, "conditions_unmet", "当前尚未满足称号条件。")
		}
		if err = state.ReconcileTitles(ctx, tx, user.ID, input.ID); err != nil {
			return nil, err
		}
		var current *string
		if err = tx.QueryRow(ctx, `SELECT (SELECT equipped_title_id::text FROM achievement_profiles WHERE user_id=$1)`, user.ID).Scan(&current); err != nil {
			return nil, err
		}
		if current == nil || *current != id {
			if _, err = tx.Exec(ctx, `UPDATE user_titles SET equipped_at=NULL WHERE user_id=$1 AND equipped_at IS NOT NULL`, user.ID); err != nil {
				return nil, err
			}
			if current != nil {
				if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "title.unequipped", "title", *current, "equip:"+input.ID+":previous", "切换称号，取消原佩戴")); err != nil {
					return nil, err
				}
			}
			if _, err = tx.Exec(ctx, `UPDATE user_titles SET equipped_at=now() WHERE user_id=$1 AND title_id=$2`, user.ID, id); err != nil {
				return nil, err
			}
			if _, err = tx.Exec(ctx, `INSERT INTO achievement_profiles(user_id,equipped_title_id) VALUES($1,$2) ON CONFLICT(user_id) DO UPDATE SET equipped_title_id=EXCLUDED.equipped_title_id`, user.ID, id); err != nil {
				return nil, err
			}
			if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "title.equipped", "title", id, "equip:"+input.ID, "佩戴称号")); err != nil {
				return nil, err
			}
		}
		result, err := catalog(ctx, tx, user.ID)
		if err != nil {
			return nil, err
		}
		if err = state.SaveCommand(ctx, tx, user.ID, input.ID, "equip", &id, hash, result); err != nil {
			return nil, err
		}
		return result, nil
	})
}
func (s *Service) unequip(w http.ResponseWriter, r *http.Request) {
	var input UnequipInput
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if !apiutil.ValidID(input.ID) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "操作标识无效。"))
		return
	}
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		hash := state.Hash(struct {
			Kind  string
			Input UnequipInput
		}{"unequip", input})
		if result, exists, err := state.Replay(ctx, tx, user.ID, input.ID, hash); err != nil {
			return nil, err
		} else if exists {
			return result, nil
		}
		var current *string
		if err := tx.QueryRow(ctx, `SELECT (SELECT equipped_title_id::text FROM achievement_profiles WHERE user_id=$1)`, user.ID).Scan(&current); err != nil {
			return nil, err
		}
		if current != nil {
			if _, err := tx.Exec(ctx, `UPDATE user_titles SET equipped_at=NULL WHERE user_id=$1 AND title_id=$2`, user.ID, *current); err != nil {
				return nil, err
			}
			if _, err := tx.Exec(ctx, `UPDATE achievement_profiles SET equipped_title_id=NULL WHERE user_id=$1`, user.ID); err != nil {
				return nil, err
			}
			if err := activity.Append(ctx, tx, activity.ServerEvent(user.ID, "title.unequipped", "title", *current, "unequip:"+input.ID, "取消称号佩戴")); err != nil {
				return nil, err
			}
		}
		result, err := catalog(ctx, tx, user.ID)
		if err != nil {
			return nil, err
		}
		if err = state.SaveCommand(ctx, tx, user.ID, input.ID, "unequip", current, hash, result); err != nil {
			return nil, err
		}
		return result, nil
	})
}
