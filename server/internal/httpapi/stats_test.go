package httpapi

import (
	"context"
	"net/url"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/stats"
	"skillatlas/internal/task"
	"skillatlas/internal/task/attempt"
	"skillatlas/internal/testdb"
	"testing"
	"time"
)

func TestStatsTimeBucketsHistoricalBindingsAndSources(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	ctx := context.Background()
	one := account(t, s, "stats@example.invalid")
	two := account(t, s, "stats-other@example.invalid")
	tr := tree(t, s, one.Token, "开发")
	tr2 := tree(t, s, one.Token, "基础")
	a := node(t, s, one.Token, tr.ID, "Go")
	b := node(t, s, one.Token, tr2.ID, "数据库")
	item := configuredTask(t, s, one.Token, task.Binding{SkillID: a.ID, RewardLevels: 2}, task.Binding{SkillID: b.ID, RewardLevels: 1})
	parse := func(v string) time.Time {
		at, err := time.Parse(time.RFC3339, v)
		if err != nil {
			t.Fatal(err)
		}
		return at
	}
	oneFocus := focusInput(a.ID, 20)
	oneFocus.EndedAt = parse("2026-10-25T15:59:59Z")
	oneFocus.StartedAt = oneFocus.EndedAt.Add(-20 * time.Second)
	oneFocus.TaskID = &item.ID
	call(t, s, "POST", "/v1/focus-sessions", one.Token, oneFocus, 201)
	twoFocus := focusInput(a.ID, 50)
	twoFocus.EndedAt = parse("2026-10-25T16:00:01Z")
	twoFocus.StartedAt = twoFocus.EndedAt.Add(-50 * time.Second)
	twoFocus.TaskID = &item.ID
	call(t, s, "POST", "/v1/focus-sessions", one.Token, twoFocus, 201)
	manual := focusInput(b.ID, 60)
	manual.Mode = "manual"
	manual.Source = "manual"
	manual.EndedAt = parse("2026-10-26T00:00:00Z")
	manual.StartedAt = manual.EndedAt.Add(-time.Minute)
	call(t, s, "POST", "/v1/focus-sessions", one.Token, manual, 201)
	failed := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(item, "failed"), 201))
	retry := attempt.RetryInput{ID: apiutil.ID(), AttemptNo: 1, Version: failed.Task.Version}
	next := decodeData[task.Task](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/retry", one.Token, retry, 200))
	firstSuccess := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(next, "success"), 201))
	undo := attempt.ReverseInput{ID: apiutil.ID()}
	undone := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/task-attempts/"+firstSuccess.Attempt.ID+"/reverse", one.Token, undo, 200))
	finalSuccess := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(undone.Task, "success"), 201))
	for _, row := range []struct{ ID, At string }{{failed.Attempt.ID, "2026-10-25T15:00:00Z"}, {firstSuccess.Attempt.ID, "2026-10-26T01:00:00Z"}, {finalSuccess.Attempt.ID, "2026-10-28T00:00:00Z"}} {
		if _, err := db.Exec(ctx, `UPDATE task_attempts SET concluded_at=$1 WHERE id=$2`, parse(row.At), row.ID); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(ctx, `UPDATE task_retry_requests SET created_at=$1 WHERE id=$2`, parse("2026-10-26T00:00:00Z"), retry.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(ctx, `UPDATE task_reversals SET created_at=$1 WHERE id=$2`, parse("2026-10-27T00:00:00Z"), undo.ID); err != nil {
		t.Fatal(err)
	}
	// 当前解绑 Go 后，历史尝试和重试仍按原快照归属。
	call(t, s, "PATCH", "/v1/tasks/"+item.ID, one.Token, task.Input{ID: item.ID, Title: item.Title, Status: "success", Skills: []task.Binding{{SkillID: b.ID, RewardLevels: 9}}, Version: finalSuccess.Task.Version}, 200)
	query := url.Values{"from": {"2026-10-25T00:00:00+08:00"}, "to": {"2026-11-02T00:00:00+08:00"}, "bucket": {"week"}}
	read := func() stats.Summary {
		return decodeData[stats.Summary](t, call(t, s, "GET", "/v1/stats/summary?"+query.Encode(), one.Token, nil, 200))
	}
	result := read()
	if result.Timezone != "Asia/Shanghai" || result.Totals.FocusSeconds != 130 || result.Totals.TimerSeconds != 70 || result.Totals.ManualSeconds != 60 || result.Totals.TimeXP != 2 || result.Totals.TaskBonusXP != 180 || result.Totals.Attempts.Total != 2 || result.Totals.Attempts.Retries != 1 || result.Totals.Attempts.SuccessRate == nil || *result.Totals.Attempts.SuccessRate != 0.5 {
		t.Fatalf("汇总或有效尝试错误: %+v", result.Totals)
	}
	if len(result.Series) != 2 || result.Series[0].Totals.FocusSeconds != 20 || result.Series[0].Totals.TimeXP != 0 || result.Series[1].Totals.FocusSeconds != 110 {
		t.Fatal("跨周边界错误")
	}
	if len(result.Sources.FocusIDs) != 3 || len(result.Sources.AttemptIDs) != 2 || len(result.Sources.RetryIDs) != 1 || len(result.Sources.GrowthIDs) != 9 {
		t.Fatal("来源数量不一致", result.Sources)
	}
	query.Set("skill_id", a.ID)
	onlyA := read()
	if onlyA.Totals.FocusSeconds != 70 || onlyA.Totals.TaskBonusXP != 120 || onlyA.Totals.Attempts.Total != 2 || onlyA.Totals.Attempts.Retries != 1 {
		t.Fatal("历史技能快照筛选错误")
	}
	query.Del("skill_id")
	query.Set("tree_id", tr.ID)
	if read().Totals.FocusSeconds != 70 {
		t.Fatal("技能树筛选错误")
	}
	query.Del("tree_id")
	query.Set("from", "2026-10-26T00:00:00+08:00")
	query.Set("bucket", "day")
	partial := read()
	if partial.Totals.FocusSeconds != 110 || partial.Totals.TimeXP != 2 || partial.Totals.Attempts.Total != 1 || partial.AllTime.Attempts.Total != 2 || len(partial.Series) != 7 {
		t.Fatal("窗口取整、累计或空桶错误")
	}
	query.Set("task_id", item.ID)
	if read().Totals.FocusSeconds != 50 {
		t.Fatal("任务专注筛选错误")
	}
	call(t, s, "GET", "/v1/stats/summary?skill_id="+a.ID, two.Token, nil, 404)
	for _, invalid := range []string{"bucket=year", "from=invalid", "from=2026-10-29T00:00:00Z&to=2026-10-28T00:00:00Z"} {
		call(t, s, "GET", "/v1/stats/summary?"+invalid, one.Token, nil, 400)
	}
	empty := decodeData[stats.Summary](t, call(t, s, "GET", "/v1/stats/summary", two.Token, nil, 200))
	if empty.Totals.Attempts.SuccessRate != nil || len(empty.Skills) != 0 {
		t.Fatal("空账号不应伪造成功率")
	}
}
