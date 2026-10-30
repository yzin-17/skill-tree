package state

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5"
	"skillatlas/internal/achievement/conditions"
	"skillatlas/internal/activity"
)

// 在改变成长事实的原事务内追加解锁或取消不再满足条件的佩戴。
func ReconcileTitles(ctx context.Context, tx pgx.Tx, user, cause string) error {
	var titles []struct {
		ID         string         `json:"id"`
		Conditions conditions.Set `json:"conditions"`
	}
	if err := tx.QueryRow(ctx, `SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'conditions',conditions_json) ORDER BY id),'[]'::jsonb) FROM titles WHERE user_id=$1`, user).Scan(&titles); err != nil {
		return err
	}
	for _, title := range titles {
		evaluation, err := Evaluate(ctx, tx, user, title.Conditions)
		if err != nil {
			return err
		}
		if evaluation.Eligible {
			tag, err := tx.Exec(ctx, `INSERT INTO user_titles(user_id,title_id,conditions_snapshot,evidence_snapshot) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING`, user, title.ID, title.Conditions, evaluation)
			if err != nil {
				return err
			}
			if tag.RowsAffected() > 0 {
				event := activity.ServerEvent(user, "title.unlocked", "title", title.ID, "title:"+title.ID+":unlocked", "解锁称号")
				event.Metadata, _ = json.Marshal(map[string]any{"cause_id": cause, "evidence": evaluation})
				if err = activity.Append(ctx, tx, event); err != nil {
					return err
				}
			}
		} else {
			tag, err := tx.Exec(ctx, `UPDATE user_titles SET equipped_at=NULL WHERE user_id=$1 AND title_id=$2 AND equipped_at IS NOT NULL`, user, title.ID)
			if err != nil {
				return err
			}
			if tag.RowsAffected() > 0 {
				if _, err = tx.Exec(ctx, `UPDATE achievement_profiles SET equipped_title_id=NULL WHERE user_id=$1 AND equipped_title_id=$2`, user, title.ID); err != nil {
					return err
				}
				event := activity.ServerEvent(user, "title.unequipped", "title", title.ID, "title:"+title.ID+":regression:"+cause, "条件回退，取消称号佩戴")
				event.Metadata, _ = json.Marshal(map[string]any{"cause_id": cause, "reason": "conditions_unmet", "evidence": evaluation})
				if err = activity.Append(ctx, tx, event); err != nil {
					return err
				}
			}
		}
	}
	return nil
}
