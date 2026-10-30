package stats

import (
	"context"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"sort"
	"time"
)

type Service struct{ DB *pgxpool.Pool }

func (s *Service) Register(mux *http.ServeMux, identity *auth.Service) {
	mux.HandleFunc("GET /v1/stats/summary", identity.Require(s.summary))
}

type filter struct {
	Skill, Tree, Task string
	From, To          time.Time
	Bucket            string
	Zone              *time.Location
}

func parse(r *http.Request, user auth.User) (filter, error) {
	q := r.URL.Query()
	f := filter{Skill: q.Get("skill_id"), Tree: q.Get("tree_id"), Task: q.Get("task_id"), Bucket: q.Get("bucket")}
	for _, id := range []string{f.Skill, f.Tree, f.Task} {
		if id != "" && !apiutil.ValidID(id) {
			return f, apiutil.Fail(400, "invalid_filter", "统计筛选标识无效。")
		}
	}
	var err error
	f.Zone, err = time.LoadLocation(user.Timezone)
	if err != nil {
		return f, err
	}
	if f.Bucket == "" {
		f.Bucket = "day"
	}
	if f.Bucket != "day" && f.Bucket != "week" && f.Bucket != "month" {
		return f, apiutil.Fail(400, "invalid_bucket", "统计粒度须为日、周或月。")
	}
	now := time.Now().In(f.Zone)
	y, m, d := now.Date()
	f.To = time.Date(y, m, d+1, 0, 0, 0, 0, f.Zone)
	f.From = f.To.AddDate(0, 0, -30)
	for key, target := range map[string]*time.Time{"from": &f.From, "to": &f.To} {
		if text := q.Get(key); text != "" {
			at, err := time.Parse(time.RFC3339Nano, text)
			if err != nil {
				return f, apiutil.Fail(400, "invalid_range", "日期范围必须使用 RFC3339 时间。")
			}
			*target = at
		}
	}
	if !f.From.Before(f.To) || f.To.Sub(f.From) > 370*24*time.Hour {
		return f, apiutil.Fail(400, "invalid_range", "请指定不超过 370 天的有效日期范围。")
	}
	return f, nil
}
func loadFacts(ctx context.Context, tx pgx.Tx, user string, f filter) ([]Fact, error) {
	args := []any{user, f.Skill, f.Tree, f.Task}
	queries := []string{
		`SELECT COALESCE(jsonb_agg(jsonb_build_object('id',f.id,'kind','focus','at',f.ended_at,'skill_ids',jsonb_build_array(f.skill_id),'seconds',f.effective_seconds,'source',f.source)),'[]'::jsonb) FROM focus_sessions f JOIN skills s ON s.id=f.skill_id WHERE f.user_id=$1 AND f.invalidated_at IS NULL AND ($2='' OR s.id::text=$2) AND ($3='' OR s.tree_id::text=$3) AND ($4='' OR f.task_id::text=$4)`,
		`SELECT COALESCE(jsonb_agg(jsonb_build_object('id',g.id,'kind','growth','at',COALESCE(f.ended_at,r.created_at,a.concluded_at,g.created_at),'skill_ids',jsonb_build_array(g.skill_id),'delta_xp',g.delta_xp,'event_type',g.event_type)),'[]'::jsonb) FROM growth_events g JOIN skills s ON s.id=g.skill_id LEFT JOIN focus_sessions f ON g.event_type='focus_accrual' AND f.id=g.source_id LEFT JOIN task_attempts a ON g.event_type IN ('task_success','reversal') AND a.id=g.source_id LEFT JOIN task_reversals r ON g.event_type='reversal' AND r.attempt_id=g.source_id WHERE g.user_id=$1 AND ($2='' OR s.id::text=$2) AND ($3='' OR s.tree_id::text=$3) AND ($4='' OR COALESCE(f.task_id,a.task_id)::text=$4)`,
		`SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a.id,'kind','attempt','at',a.concluded_at,'result',a.result,'skill_ids',COALESCE((SELECT jsonb_agg(s.skill_id) FROM task_attempt_skills s WHERE s.attempt_id=a.id),'[]'::jsonb))),'[]'::jsonb) FROM task_attempts a WHERE a.user_id=$1 AND a.reversed_at IS NULL AND ($4='' OR a.task_id::text=$4) AND (($2='' AND $3='') OR EXISTS(SELECT 1 FROM task_attempt_skills ats JOIN skills s ON s.id=ats.skill_id WHERE ats.attempt_id=a.id AND ($2='' OR s.id::text=$2) AND ($3='' OR s.tree_id::text=$3)))`,
		`SELECT COALESCE(jsonb_agg(jsonb_build_object('id',rr.id,'kind','retry','at',rr.created_at,'skill_ids',COALESCE((SELECT jsonb_agg(s.skill_id) FROM task_attempt_skills s WHERE s.attempt_id=a.id),'[]'::jsonb))),'[]'::jsonb) FROM task_retry_requests rr JOIN task_attempts a ON a.task_id=rr.task_id AND a.attempt_no=rr.previous_attempt_no WHERE rr.user_id=$1 AND ($4='' OR rr.task_id::text=$4) AND (($2='' AND $3='') OR EXISTS(SELECT 1 FROM task_attempt_skills ats JOIN skills s ON s.id=ats.skill_id WHERE ats.attempt_id=a.id AND ($2='' OR s.id::text=$2) AND ($3='' OR s.tree_id::text=$3)))`,
	}
	facts := []Fact{}
	for _, query := range queries {
		var values []Fact
		if err := tx.QueryRow(ctx, query, args...).Scan(&values); err != nil {
			return nil, err
		}
		facts = append(facts, values...)
	}
	sort.Slice(facts, func(i, j int) bool {
		if facts[i].At.Equal(facts[j].At) {
			return facts[i].ID < facts[j].ID
		}
		return facts[i].At.Before(facts[j].At)
	})
	return facts, nil
}
func (s *Service) summary(w http.ResponseWriter, r *http.Request) {
	user := auth.Current(r.Context())
	f, err := parse(r, user)
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	ctx := r.Context()
	tx, err := s.DB.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	defer tx.Rollback(ctx)
	result, err := read(ctx, tx, user.ID, f)
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, result)
}
func read(ctx context.Context, tx pgx.Tx, user string, f filter) (Summary, error) {
	result := Summary{Timezone: f.Zone.String(), From: f.From, To: f.To, Bucket: f.Bucket, Series: []Bucket{}, Skills: []SkillSummary{}, Sources: EmptySources(), HistoryScope: "account"}
	// 引用筛选必须属于当前账号；空数据与他人对象有明确区别。
	for table, id := range map[string]string{"skills": f.Skill, "skill_trees": f.Tree, "tasks": f.Task} {
		if id != "" {
			var exists bool
			if err := tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM "+table+" WHERE user_id=$1 AND id=$2)", user, id).Scan(&exists); err != nil {
				return result, err
			}
			if !exists {
				return result, apiutil.NotFound()
			}
		}
	}
	facts, err := loadFacts(ctx, tx, user, f)
	if err != nil {
		return result, err
	}
	if err = tx.QueryRow(ctx, `SELECT COALESCE(jsonb_agg(jsonb_build_object('skill_id',id,'tree_id',tree_id,'name',name) ORDER BY name,id),'[]'::jsonb) FROM skills WHERE user_id=$1 AND ($2='' OR id::text=$2) AND ($3='' OR tree_id::text=$3)`, user, f.Skill, f.Tree).Scan(&result.Skills); err != nil {
		return result, err
	}
	skillIndex := map[string]int{}
	for i, skill := range result.Skills {
		skillIndex[skill.SkillID] = i
	}
	buckets := map[int64]int{}
	for start := BucketStart(f.From, f.Bucket, f.Zone); start.Before(f.To); start = NextBucket(start, f.Bucket) {
		buckets[start.Unix()] = len(result.Series)
		result.Series = append(result.Series, Bucket{Start: start, Label: start.Format("2006-01-02"), Sources: EmptySources()})
	}
	for _, fact := range facts {
		result.AllTime.Add(fact)
		if fact.At.Before(f.From) || !fact.At.Before(f.To) {
			continue
		}
		result.Totals.Add(fact)
		result.Sources.Add(fact)
		index := buckets[BucketStart(fact.At, f.Bucket, f.Zone).Unix()]
		result.Series[index].Totals.Add(fact)
		result.Series[index].Sources.Add(fact)
		for _, id := range fact.SkillIDs {
			if i, ok := skillIndex[id]; ok {
				result.Skills[i].Totals.Add(fact)
			}
		}
	}
	if err = tx.QueryRow(ctx, `SELECT COALESCE(jsonb_agg(to_jsonb(c)-'user_id' ORDER BY confirmed_at DESC,id),'[]'::jsonb) FROM career_transitions c WHERE user_id=$1 AND confirmed_at>=$2 AND confirmed_at<$3`, user, f.From, f.To).Scan(&result.CareerHistory); err != nil {
		return result, err
	}
	if err = tx.QueryRow(ctx, `SELECT COALESCE(jsonb_agg(to_jsonb(e)-'user_id'-'source_key' ORDER BY occurred_at DESC,id),'[]'::jsonb) FROM activity_events e WHERE user_id=$1 AND type IN ('title.unlocked','title.equipped','title.unequipped') AND occurred_at>=$2 AND occurred_at<$3`, user, f.From, f.To).Scan(&result.TitleHistory); err != nil {
		return result, err
	}
	return result, nil
}
