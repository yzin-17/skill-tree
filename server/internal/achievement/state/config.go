package state

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/jackc/pgx/v5"
	"skillatlas/internal/achievement/conditions"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/skill"
	"slices"
	"strings"
	"unicode/utf8"
)

type Config struct {
	ID          string         `json:"id"`
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Conditions  conditions.Set `json:"conditions"`
	Version     int            `json:"version"`
}

func (v *Config) Validate(create bool, icon string) error {
	v.Name = strings.TrimSpace(v.Name)
	if !apiutil.ValidID(v.ID) || utf8.RuneCountInString(v.Name) < 1 || utf8.RuneCountInString(v.Name) > 80 || utf8.RuneCountInString(v.Description) > 4000 || !slices.Contains(skill.Icons, icon) || (create && v.Version != 0) || (!create && v.Version < 1) {
		return apiutil.Fail(400, "invalid_achievement", "名称、图标或版本无效。")
	}
	return v.Conditions.Validate()
}
func ValidateReferences(ctx context.Context, q skill.Queryer, user string, set conditions.Set) error {
	for _, c := range set.All {
		if c.SkillID != nil {
			if _, err := skill.ByID(ctx, q, user, *c.SkillID); err != nil {
				return err
			}
		}
		if c.TaskID != nil {
			var exists bool
			if err := q.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM tasks WHERE id=$1 AND user_id=$2)`, *c.TaskID, user).Scan(&exists); err != nil {
				return err
			}
			if !exists {
				return apiutil.NotFound()
			}
		}
	}
	return nil
}
func RetainReferences(ctx context.Context, tx pgx.Tx, user, kind, id string, set conditions.Set) error {
	for _, c := range set.All {
		refType := ""
		var ref *string
		if c.SkillID != nil {
			refType = "skill"
			ref = c.SkillID
		}
		if c.TaskID != nil {
			refType = "task"
			ref = c.TaskID
		}
		if ref == nil {
			continue
		}
		if _, err := tx.Exec(ctx, `INSERT INTO achievement_references(entity_type,entity_id,user_id,reference_type,reference_id,skill_id,task_id) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT DO NOTHING`, kind, id, user, refType, *ref, c.SkillID, c.TaskID); err != nil {
			return err
		}
	}
	return nil
}
func Hash(value any) string {
	data, _ := json.Marshal(value)
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
func Replay(ctx context.Context, tx pgx.Tx, user, id, hash string) (json.RawMessage, bool, error) {
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "achievement-command:"+id); err != nil {
		return nil, false, err
	}
	var owner, original string
	var result json.RawMessage
	err := tx.QueryRow(ctx, `SELECT user_id::text,request_hash,result_json FROM achievement_commands WHERE id=$1`, id).Scan(&owner, &original, &result)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	if owner != user {
		return nil, false, apiutil.NotFound()
	}
	if original != hash {
		return nil, false, apiutil.Fail(409, "id_conflict", "相同操作标识的内容不同。")
	}
	return result, true, nil
}
func SaveCommand(ctx context.Context, tx pgx.Tx, user, id, kind string, target *string, hash string, result any) error {
	_, err := tx.Exec(ctx, `INSERT INTO achievement_commands(id,user_id,kind,target_id,request_hash,result_json) VALUES($1,$2,$3,$4,$5,$6)`, id, user, kind, target, hash, result)
	return err
}
