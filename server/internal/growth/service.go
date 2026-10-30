package growth

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/skill"
)

func Read(ctx context.Context, q skill.Queryer, user, id string) (Progress, error) {
	if _, err := skill.ByID(ctx, q, user, id); err != nil {
		return Progress{}, err
	}
	var seconds, timeXP, bonus int64
	err := q.QueryRow(ctx, `SELECT COALESCE((SELECT sum(effective_seconds) FROM focus_sessions WHERE user_id=$1 AND skill_id=$2 AND invalidated_at IS NULL),0),COALESCE(sum(delta_xp) FILTER(WHERE event_type='focus_accrual'),0),COALESCE(sum(delta_xp) FILTER(WHERE event_type<>'focus_accrual'),0) FROM growth_events WHERE user_id=$1 AND skill_id=$2`, user, id).Scan(&seconds, &timeXP, &bonus)
	if err != nil {
		return Progress{}, err
	}
	result := Calculate(id, seconds, timeXP, bonus)
	err = q.QueryRow(ctx, `SELECT COALESCE(jsonb_agg(jsonb_build_object('skill_id',id,'name',name,'required_level',required_level,'current_level',current_level) ORDER BY id),'[]'::jsonb) FROM (SELECT s.id,s.name,l.required_level,(1+floor(COALESCE((SELECT sum(g.delta_xp) FROM growth_events g WHERE g.skill_id=s.id AND g.user_id=$1),0)/60))::bigint AS current_level FROM skill_links l JOIN skills s ON s.id=l.to_skill_id WHERE l.user_id=$1 AND l.from_skill_id=$2 AND l.link_type='prerequisite' AND l.deleted_at IS NULL) conditions WHERE current_level<required_level`, user, id).Scan(&result.MissingPrerequisites)
	if err != nil {
		return Progress{}, err
	}
	result.Unlocked = len(result.MissingPrerequisites) == 0
	return result, nil
}
func Record(ctx context.Context, tx pgx.Tx, user, skillID, kind, source string, delta int64, note string, reverses *string) (string, error) {
	id := apiutil.ID()
	_, err := tx.Exec(ctx, `INSERT INTO growth_events(id,user_id,skill_id,event_type,source_id,delta_xp,note,reverses_event_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, id, user, skillID, kind, source, delta, note, reverses)
	if err != nil {
		return "", err
	}
	if delta != 0 {
		entity := "task_attempt"
		if kind == "focus_accrual" {
			entity = "focus_session"
		}
		event := activity.ServerEvent(user, "growth.accrued", entity, source, "growth:"+id, note, skillID)
		event.Metadata, _ = json.Marshal(map[string]any{"growth_event_id": id, "skill_id": skillID, "delta_xp": delta, "event_type": kind, "reverses_event_id": reverses})
		if err = activity.Append(ctx, tx, event); err != nil {
			return "", err
		}
	}
	return id, nil
}
func LevelUp(ctx context.Context, tx pgx.Tx, user, source string, before, after Progress) error {
	if after.Level <= before.Level {
		return nil
	}
	event := activity.ServerEvent(user, "skill.level_up", "skill", after.SkillID, "level:"+source+":"+after.SkillID, "技能升级", after.SkillID)
	event.Metadata, _ = json.Marshal(map[string]any{"previous_level": before.Level, "level": after.Level, "source_id": source})
	return activity.Append(ctx, tx, event)
}

type Service struct{ DB *pgxpool.Pool }

func (s *Service) Register(mux *http.ServeMux, identity *auth.Service) {
	mux.HandleFunc("GET /v1/growth-events/{id}", identity.Require(s.detail))
	mux.HandleFunc("GET /v1/skills/{id}/progress", identity.Require(s.get))
	mux.HandleFunc("GET /v1/progress", identity.Require(s.list))
}
func (s *Service) get(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !apiutil.ValidID(id) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "技能标识无效。"))
		return
	}
	p, err := Read(r.Context(), s.DB, auth.Current(r.Context()).ID, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			err = apiutil.NotFound()
		}
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, p)
}
func (s *Service) list(w http.ResponseWriter, r *http.Request) {
	user := auth.Current(r.Context()).ID
	rows, err := s.DB.Query(r.Context(), `SELECT id::text FROM skills WHERE user_id=$1 ORDER BY id`, user)
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			apiutil.WriteError(w, err)
			return
		}
		ids = append(ids, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	items := []Progress{}
	for _, id := range ids {
		p, err := Read(r.Context(), s.DB, user, id)
		if err != nil {
			apiutil.WriteError(w, err)
			return
		}
		items = append(items, p)
	}
	apiutil.Write(w, 200, items)
}
