package httpapi

import (
	"context"
	"fmt"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/focus"
	"skillatlas/internal/growth"
	"skillatlas/internal/task"
	"skillatlas/internal/testdb"
	"sync"
	"testing"
	"time"
)

func focusInput(skill string, seconds int64) focus.Input {
	at := time.Now().UTC().Truncate(time.Second)
	return focus.Input{ID: apiutil.ID(), SkillID: skill, Mode: "count_up", Source: "timer", EffectiveSeconds: seconds, StartedAt: at.Add(-time.Duration(seconds) * time.Second), EndedAt: at}
}
func TestFocusAccrualReplayConcurrencyAndRollback(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	ctx := context.Background()
	owner := account(t, s, "focus@example.invalid")
	other := account(t, s, "other-focus@example.invalid")
	tr := tree(t, s, owner.Token, "后端")
	sk := node(t, s, owner.Token, tr.ID, "Go")
	taskConfig := task.Input{ID: apiutil.ID(), Title: "登录接口", Status: "todo", Skills: []task.Binding{{SkillID: sk.ID, RewardLevels: 2}}}
	taskItem := decodeData[task.Task](t, call(t, s, "POST", "/v1/tasks", owner.Token, taskConfig, 201))
	initial := decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+sk.ID+"/progress", owner.Token, nil, 200))
	if initial.Level != 1 || initial.TotalXP != 0 || initial.TotalFocusSeconds != 0 {
		t.Fatal("初始进度错误")
	}
	first := focusInput(sk.ID, 20)
	first.TaskID = &taskItem.ID
	firstResult := decodeData[focus.Settlement](t, call(t, s, "POST", "/v1/focus-sessions", owner.Token, first, 201))
	if firstResult.AwardedXP != 0 {
		t.Fatal("20 秒不应提前取整")
	}
	second := focusInput(sk.ID, 50)
	second.TaskID = &taskItem.ID
	result := decodeData[focus.Settlement](t, call(t, s, "POST", "/v1/focus-sessions", owner.Token, second, 201))
	if result.AwardedXP != 1 || result.SettledProgress.TotalFocusSeconds != 70 || result.SettledProgress.TotalXP != 1 {
		t.Fatal("20+50 秒累计错误")
	}
	replay := decodeData[focus.Settlement](t, call(t, s, "POST", "/v1/focus-sessions", owner.Token, first, 201))
	if replay.SettledProgress.TotalXP != firstResult.SettledProgress.TotalXP || replay.AwardedXP != 0 {
		t.Fatal("重放改变原结算快照")
	}
	conflicting := first
	conflicting.Note = "改变原内容"
	call(t, s, "POST", "/v1/focus-sessions", owner.Token, conflicting, 409)
	call(t, s, "POST", "/v1/focus-sessions", other.Token, first, 404)
	forbidden := focusInput(sk.ID, 60)
	call(t, s, "POST", "/v1/focus-sessions", other.Token, forbidden, 404)
	concurrent := focusInput(sk.ID, 60)
	var wg sync.WaitGroup
	for range 6 {
		wg.Add(1)
		go func() { defer wg.Done(); call(t, s, "POST", "/v1/focus-sessions", owner.Token, concurrent, 201) }()
	}
	wg.Wait()
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			call(t, s, "POST", "/v1/focus-sessions", owner.Token, focusInput(sk.ID, 15), 201)
		}()
	}
	wg.Wait()
	current := decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+sk.ID+"/progress", owner.Token, nil, 200))
	if current.TotalFocusSeconds != 190 || current.TotalXP != 3 || current.TaskBonusXP != 0 {
		t.Fatal("并发提交重复入账或丢失秒数")
	}
	broken := focusInput(sk.ID, 80)
	_, err := db.Exec(ctx, fmt.Sprintf(`CREATE FUNCTION reject_test_growth() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.source_id='%s'::uuid THEN RAISE EXCEPTION '隔离测试故障'; END IF; RETURN NEW; END $$; CREATE TRIGGER reject_test_growth BEFORE INSERT ON growth_events FOR EACH ROW EXECUTE FUNCTION reject_test_growth();`, broken.ID))
	if err != nil {
		t.Fatal(err)
	}
	call(t, s, "POST", "/v1/focus-sessions", owner.Token, broken, 500)
	var count int
	if err = db.QueryRow(ctx, `SELECT count(*) FROM focus_sessions WHERE id=$1`, broken.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("成长故障后留下会话")
	}
	if _, err = db.Exec(ctx, `DROP TRIGGER reject_test_growth ON growth_events; DROP FUNCTION reject_test_growth()`); err != nil {
		t.Fatal(err)
	}
	restored := decodeData[focus.Settlement](t, call(t, s, "POST", "/v1/focus-sessions", owner.Token, broken, 201))
	if restored.SettledProgress.TotalFocusSeconds != 270 || restored.SettledProgress.TotalXP != 4 {
		t.Fatal("回滚后重试错误")
	}
	manual := focusInput(sk.ID, 3600)
	manual.Source = "manual"
	manual.Mode = "manual"
	manualResult := decodeData[focus.Settlement](t, call(t, s, "POST", "/v1/focus-sessions", owner.Token, manual, 201))
	if manualResult.AwardedXP != 60 || manualResult.Session.Source != "manual" || manualResult.SettledProgress.Level != 2 || manualResult.SettledProgress.XPCurrent != 4 {
		t.Fatal("补录或跨级错误")
	}
	call(t, s, "DELETE", "/v1/skills/"+sk.ID+"?version=1", owner.Token, nil, 409)
	var rows, events int
	if err = db.QueryRow(ctx, `SELECT count(*) FROM focus_sessions WHERE user_id=$1`, owner.User.ID).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if err = db.QueryRow(ctx, `SELECT count(*) FROM growth_events WHERE user_id=$1`, owner.User.ID).Scan(&events); err != nil {
		t.Fatal(err)
	}
	if rows != 9 || events != 9 {
		t.Fatalf("副作用数量错误 sessions=%d growth=%d", rows, events)
	}
}
