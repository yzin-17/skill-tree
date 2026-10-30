package state

import (
	"context"
	"fmt"
	"skillatlas/internal/achievement/conditions"
	"skillatlas/internal/skill"
)

func Evaluate(ctx context.Context, q skill.Queryer, user string, set conditions.Set) (conditions.Evaluation, error) {
	if err := set.Validate(); err != nil {
		return conditions.Evaluation{}, err
	}
	facts := []conditions.Fact{}
	for _, c := range set.All {
		var table, where, aggregate, source string
		args := []any{user}
		switch c.Type {
		case "skill_level":
			table = "growth_events"
			where = "user_id=$1 AND skill_id=$2"
			args = append(args, *c.SkillID)
			aggregate = "(1+floor(COALESCE(sum(delta_xp),0)/60))::bigint"
			source = "growth_event"
		case "focus_minutes":
			table = "focus_sessions"
			where = "user_id=$1 AND skill_id=$2 AND source='timer' AND invalidated_at IS NULL"
			args = append(args, *c.SkillID)
			aggregate = "floor(COALESCE(sum(effective_seconds),0)/60)::bigint"
			source = "focus_session"
		case "task_success_count", "specific_task_success":
			table = "task_attempts"
			where = "user_id=$1 AND result='success' AND reversed_at IS NULL"
			aggregate = "count(*)"
			source = "task_attempt"
			if c.TaskID != nil {
				where += " AND task_id=$2"
				args = append(args, *c.TaskID)
			} else if c.SkillID != nil {
				where += " AND EXISTS(SELECT 1 FROM task_attempt_skills s WHERE s.attempt_id=task_attempts.id AND s.skill_id=$2)"
				args = append(args, *c.SkillID)
			}
		}
		var fact conditions.Fact
		var count int64
		fact.SourceType = source
		query := fmt.Sprintf("SELECT %s,count(*) FROM %s WHERE %s", aggregate, table, where)
		if err := q.QueryRow(ctx, query, args...).Scan(&fact.Current, &count); err != nil {
			return conditions.Evaluation{}, err
		}
		query = fmt.Sprintf("SELECT COALESCE(jsonb_agg(id),'[]'::jsonb) FROM (SELECT id::text FROM %s WHERE %s ORDER BY id LIMIT 200) sources", table, where)
		if err := q.QueryRow(ctx, query, args...).Scan(&fact.SourceIDs); err != nil {
			return conditions.Evaluation{}, err
		}
		fact.Truncated = count > 200
		facts = append(facts, fact)
	}
	return conditions.Evaluate(set, facts)
}
