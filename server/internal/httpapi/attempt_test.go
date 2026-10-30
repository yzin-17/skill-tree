package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/growth"
	"skillatlas/internal/task"
	"skillatlas/internal/task/attempt"
	"skillatlas/internal/testdb"
	"sync"
	"testing"
)

func configuredTask(t *testing.T, s *Server, token string, bindings ...task.Binding) task.Task {
	return decodeData[task.Task](t, call(t, s, "POST", "/v1/tasks", token, task.Input{ID: apiutil.ID(), Title: "任务结算验收", Status: "in_progress", Skills: bindings}, 201))
}
func concludeInput(item task.Task, result string) attempt.Conclusion {
	return attempt.Conclusion{ID: apiutil.ID(), AttemptNo: item.CurrentAttemptNo, Version: item.Version, Result: result, Reason: "验收记录"}
}
func TestAttemptSettlementAtomicitySnapshotsAndConcurrency(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	ctx := context.Background()
	owner := account(t, s, "attempt@example.invalid")
	other := account(t, s, "attempt-other@example.invalid")
	tr := tree(t, s, owner.Token, "结算")
	goSkill := node(t, s, owner.Token, tr.ID, "Go")
	dbSkill := node(t, s, owner.Token, tr.ID, "数据库")
	failedTask := configuredTask(t, s, owner.Token, task.Binding{SkillID: goSkill.ID, RewardLevels: 2})
	call(t, s, "POST", "/v1/focus-sessions", owner.Token, focusInput(goSkill.ID, 1800), 201)
	failure := concludeInput(failedTask, "failed")
	result := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+failedTask.ID+"/attempts", owner.Token, failure, 201))
	if len(result.Rewards) != 0 || len(result.Attempt.SkillSnapshot) != 1 || result.Task.Status != "failed" {
		t.Fatal("失败结算或技能快照错误")
	}
	p := decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+goSkill.ID+"/progress", owner.Token, nil, 200))
	if p.TimeXP != 30 || p.TaskBonusXP != 0 {
		t.Fatal("失败改动了时间经验或奖励")
	}
	item := configuredTask(t, s, owner.Token, task.Binding{SkillID: goSkill.ID, RewardLevels: 2}, task.Binding{SkillID: dbSkill.ID, RewardLevels: 1})
	input := concludeInput(item, "success")
	path := "/v1/tasks/" + item.ID + "/attempts"
	var wg sync.WaitGroup
	for range 5 {
		wg.Add(1)
		go func() { defer wg.Done(); call(t, s, "POST", path, owner.Token, input, 201) }()
	}
	wg.Wait()
	settled := decodeData[attempt.Settlement](t, call(t, s, "POST", path, owner.Token, input, 201))
	if len(settled.Rewards) != 2 || settled.Task.Status != "success" {
		t.Fatal("多技能结算缺失")
	}
	changed := input
	changed.Reason = "冲突内容"
	call(t, s, "POST", path, owner.Token, changed, 409)
	call(t, s, "POST", path, other.Token, input, 404)
	changed = input
	changed.ID = apiutil.ID()
	call(t, s, "POST", path, owner.Token, changed, 409)
	edit := task.Input{ID: item.ID, Title: item.Title, Status: "success", Skills: []task.Binding{{SkillID: goSkill.ID, RewardLevels: 9}}, Version: settled.Task.Version}
	call(t, s, "PATCH", "/v1/tasks/"+item.ID, owner.Token, edit, 200)
	replay := decodeData[attempt.Settlement](t, call(t, s, "POST", path, owner.Token, input, 201))
	if replay.Rewards[0].XPAmount != settled.Rewards[0].XPAmount || replay.Attempt.ConcludedAt != settled.Attempt.ConcludedAt {
		t.Fatal("编辑配置改变了历史结算")
	}
	p = decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+goSkill.ID+"/progress", owner.Token, nil, 200))
	if p.TotalXP != 150 || p.TaskBonusXP != 120 {
		t.Fatal("成功奖励重复或错误")
	}
	brokenTask := configuredTask(t, s, owner.Token, task.Binding{SkillID: goSkill.ID, RewardLevels: 1}, task.Binding{SkillID: dbSkill.ID, RewardLevels: 1})
	broken := concludeInput(brokenTask, "success")
	_, err := db.Exec(ctx, fmt.Sprintf(`CREATE FUNCTION reject_attempt_reward() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.attempt_id='%s'::uuid THEN RAISE EXCEPTION '隔离奖励故障'; END IF; RETURN NEW; END $$;CREATE TRIGGER reject_attempt_reward BEFORE INSERT ON task_rewards FOR EACH ROW EXECUTE FUNCTION reject_attempt_reward();`, broken.ID))
	if err != nil {
		t.Fatal(err)
	}
	call(t, s, "POST", "/v1/tasks/"+brokenTask.ID+"/attempts", owner.Token, broken, 500)
	var count int
	if err = db.QueryRow(ctx, `SELECT (SELECT count(*) FROM task_attempts WHERE id=$1)+(SELECT count(*) FROM growth_events WHERE source_id=$1)+(SELECT count(*) FROM activity_events WHERE entity_id=$1)`, broken.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("事务故障留下部分结算", err, count)
	}
	if _, err = db.Exec(ctx, `DROP TRIGGER reject_attempt_reward ON task_rewards;DROP FUNCTION reject_attempt_reward()`); err != nil {
		t.Fatal(err)
	}
	call(t, s, "POST", "/v1/tasks/"+brokenTask.ID+"/attempts", owner.Token, broken, 201)
	// 不同请求 ID 并发争抢同一编号，只允许一次成功。
	raceTask := configuredTask(t, s, owner.Token, task.Binding{SkillID: goSkill.ID, RewardLevels: 0})
	codes := make(chan int, 4)
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			body, _ := json.Marshal(concludeInput(raceTask, "success"))
			req := httptest.NewRequest("POST", "/v1/tasks/"+raceTask.ID+"/attempts", bytes.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+owner.Token)
			rec := httptest.NewRecorder()
			s.ServeHTTP(rec, req)
			codes <- rec.Code
		}()
	}
	wg.Wait()
	close(codes)
	successes := 0
	for code := range codes {
		if code == 201 {
			successes++
		} else if code != 409 {
			t.Fatal("并发返回异常", code)
		}
	}
	if successes != 1 {
		t.Fatal("不同 ID 重复结算")
	}
}
