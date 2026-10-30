package httpapi

import (
	"context"
	"fmt"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/growth"
	"skillatlas/internal/task"
	"skillatlas/internal/task/attempt"
	"skillatlas/internal/testdb"
	"sync"
	"testing"
)

func TestRetryReversalAndEffectiveAttemptStatistics(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	ctx := context.Background()
	one := account(t, s, "retry-one@example.invalid")
	two := account(t, s, "retry-two@example.invalid")
	tr := tree(t, s, one.Token, "重试与补偿")
	a := node(t, s, one.Token, tr.ID, "Go")
	b := node(t, s, one.Token, tr.ID, "数据库")
	item := configuredTask(t, s, one.Token, task.Binding{SkillID: a.ID, RewardLevels: 2}, task.Binding{SkillID: b.ID, RewardLevels: 1})
	if item.AttemptSummary.SuccessRate != nil || item.AttemptSummary.Total != 0 {
		t.Fatal("零分母应无成功率")
	}
	failed := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(item, "failed"), 201))
	if failed.Task.AttemptSummary.Failures != 1 || failed.Task.AttemptSummary.Successes != 0 {
		t.Fatal("失败统计错误")
	}
	retry := attempt.RetryInput{ID: apiutil.ID(), AttemptNo: 1, Version: failed.Task.Version}
	retryPath := "/v1/tasks/" + item.ID + "/retry"
	next := decodeData[task.Task](t, call(t, s, "POST", retryPath, one.Token, retry, 200))
	if next.CurrentAttemptNo != 2 || next.Status != "in_progress" || next.AttemptSummary.Retries != 1 {
		t.Fatal("重试未打开唯一下一编号")
	}
	replay := decodeData[task.Task](t, call(t, s, "POST", retryPath, one.Token, retry, 200))
	if replay.CurrentAttemptNo != 2 {
		t.Fatal("重放重复推进编号")
	}
	call(t, s, "POST", retryPath, two.Token, retry, 404)
	invalid := retry
	invalid.ID = apiutil.ID()
	call(t, s, "POST", retryPath, one.Token, invalid, 409)
	call(t, s, "POST", "/v1/task-attempts/"+failed.Attempt.ID+"/reverse", one.Token, attempt.ReverseInput{ID: apiutil.ID()}, 409)
	success := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(next, "success"), 201))
	stats := success.Task.AttemptSummary
	if stats.Total != 2 || stats.Successes != 1 || stats.Failures != 1 || stats.SuccessRate == nil || *stats.SuccessRate != 0.5 {
		t.Fatal("失败后成功应为 50%，多技能不重复计数")
	}
	call(t, s, "POST", retryPath, one.Token, attempt.RetryInput{ID: apiutil.ID(), AttemptNo: 2, Version: success.Task.Version}, 409)
	reverse := attempt.ReverseInput{ID: apiutil.ID(), Reason: "误结算，重新执行"}
	reversePath := "/v1/task-attempts/" + success.Attempt.ID + "/reverse"
	_, err := db.Exec(ctx, fmt.Sprintf(`CREATE FUNCTION reject_compensation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.event_type='reversal' AND NEW.source_id='%s'::uuid THEN RAISE EXCEPTION '隔离补偿故障'; END IF; RETURN NEW; END $$;CREATE TRIGGER reject_compensation BEFORE INSERT ON growth_events FOR EACH ROW EXECUTE FUNCTION reject_compensation();`, success.Attempt.ID))
	if err != nil {
		t.Fatal(err)
	}
	call(t, s, "POST", reversePath, one.Token, reverse, 500)
	var count int
	if err = db.QueryRow(ctx, `SELECT count(*) FROM task_reversals WHERE attempt_id=$1`, success.Attempt.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("故障留下撤销事实")
	}
	still := decodeData[task.Task](t, call(t, s, "GET", "/v1/tasks/"+item.ID, one.Token, nil, 200))
	if still.Status != "success" || still.AttemptSummary.Total != 2 {
		t.Fatal("失败补偿改变了状态或统计")
	}
	if _, err = db.Exec(ctx, `DROP TRIGGER reject_compensation ON growth_events;DROP FUNCTION reject_compensation()`); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	for range 5 {
		wg.Add(1)
		go func() { defer wg.Done(); call(t, s, "POST", reversePath, one.Token, reverse, 200) }()
	}
	wg.Wait()
	reversed := decodeData[attempt.Settlement](t, call(t, s, "POST", reversePath, one.Token, reverse, 200))
	if reversed.Reversal == nil || reversed.Attempt.ReversedAt == nil || reversed.Task.CurrentAttemptNo != 3 || reversed.Task.Status != "in_progress" || reversed.Task.AttemptSummary.Total != 1 || reversed.Task.AttemptSummary.Successes != 0 || reversed.Task.AttemptSummary.Retries != 1 {
		t.Fatal("补偿后状态、统计或重试计数错误")
	}
	call(t, s, "POST", reversePath, one.Token, attempt.ReverseInput{ID: apiutil.ID()}, 409)
	call(t, s, "POST", reversePath, two.Token, reverse, 404)
	conflict := reverse
	conflict.Reason = "不同内容"
	call(t, s, "POST", reversePath, one.Token, conflict, 409)
	for _, id := range []string{a.ID, b.ID} {
		p := decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+id+"/progress", one.Token, nil, 200))
		if p.TaskBonusXP != 0 || p.Level != 1 {
			t.Fatal("补偿重复扣减或未扣减")
		}
	}
	history := decodeData[attempt.History](t, call(t, s, "GET", "/v1/tasks/"+item.ID+"/attempts", one.Token, nil, 200))
	if len(history.Items) != 2 || history.Items[0].Reversal == nil || len(history.Items[0].Rewards) != 2 || history.Items[1].Attempt.Result != "failed" {
		t.Fatal("原始失败、奖励或撤销历史丢失")
	}
	call(t, s, "GET", "/v1/tasks/"+item.ID+"/attempts", two.Token, nil, 404)
	call(t, s, "GET", "/v1/task-attempts/"+success.Attempt.ID, two.Token, nil, 404)
	// 撤销失败也开启下一编号，零分母恢复为 null；取消本身不增加尝试。
	other := configuredTask(t, s, one.Token)
	failure := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+other.ID+"/attempts", one.Token, concludeInput(other, "failed"), 201))
	undone := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/task-attempts/"+failure.Attempt.ID+"/reverse", one.Token, attempt.ReverseInput{ID: apiutil.ID()}, 200))
	if undone.Task.AttemptSummary.SuccessRate != nil || undone.Task.AttemptSummary.Total != 0 || len(undone.Rewards) != 0 {
		t.Fatal("失败撤销口径错误")
	}
	canceled := decodeData[task.Task](t, call(t, s, "PATCH", "/v1/tasks/"+other.ID, one.Token, task.Input{ID: other.ID, Title: other.Title, Status: "canceled", Version: undone.Task.Version}, 200))
	if canceled.AttemptSummary.Total != 0 {
		t.Fatal("取消增加了尝试")
	}
}
