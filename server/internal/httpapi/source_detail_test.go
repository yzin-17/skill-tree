package httpapi

import (
	"context"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/growth"
	"skillatlas/internal/task"
	"skillatlas/internal/task/attempt"
	"skillatlas/internal/testdb"
	"testing"
)

func TestStatsSourceDetailIsolationAndReversalChain(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	one := account(t, s, "source-one@example.invalid")
	two := account(t, s, "source-two@example.invalid")
	tr := tree(t, s, one.Token, "来源")
	skill := node(t, s, one.Token, tr.ID, "阅读")
	item := configuredTask(t, s, one.Token, task.Binding{SkillID: skill.ID, RewardLevels: 2})
	failed := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(item, "failed"), 201))
	retry := attempt.RetryInput{ID: apiutil.ID(), AttemptNo: 1, Version: failed.Task.Version}
	next := decodeData[task.Task](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/retry", one.Token, retry, 200))
	detail := decodeData[attempt.RetryDetail](t, call(t, s, "GET", "/v1/task-retries/"+retry.ID, one.Token, nil, 200))
	if detail.PreviousAttemptID != failed.Attempt.ID || detail.NextAttemptNo != 2 || detail.TaskID != item.ID {
		t.Fatal("重试来源错误")
	}
	success := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(next, "success"), 201))
	bonus := success.Rewards[0].GrowthEventID
	call(t, s, "POST", "/v1/task-attempts/"+success.Attempt.ID+"/reverse", one.Token, attempt.ReverseInput{ID: apiutil.ID()}, 200)
	var reverseID string
	if err := db.QueryRow(context.Background(), `SELECT id::text FROM growth_events WHERE reverses_event_id=$1`, bonus).Scan(&reverseID); err != nil {
		t.Fatal(err)
	}
	value := decodeData[growth.EventDetail](t, call(t, s, "GET", "/v1/growth-events/"+reverseID, one.Token, nil, 200))
	if value.DeltaXP != -120 || value.SourceID != success.Attempt.ID || value.ReversesEventID == nil || *value.ReversesEventID != bonus {
		t.Fatal("补偿链错误")
	}
	for _, route := range []string{"/v1/task-retries/" + retry.ID, "/v1/growth-events/" + reverseID} {
		call(t, s, "GET", route, two.Token, nil, 404)
		call(t, s, "GET", route, "", nil, 401)
		call(t, s, "GET", route, one.Token, nil, 200)
	}
	for _, prefix := range []string{"/v1/task-retries/", "/v1/growth-events/"} {
		call(t, s, "GET", prefix+apiutil.ID(), one.Token, nil, 404)
		call(t, s, "GET", prefix+"invalid", one.Token, nil, 400)
	}
	var count int
	if err := db.QueryRow(context.Background(), `SELECT count(*) FROM growth_events WHERE user_id=$1`, one.User.ID).Scan(&count); err != nil || count != 2 {
		t.Fatalf("重复读取改变了流水：%d, %v", count, err)
	}
}
