package httpapi

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"skillatlas/internal/achievement/career"
	"skillatlas/internal/achievement/state"
	"skillatlas/internal/achievement/title"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	dataexport "skillatlas/internal/export"
	"skillatlas/internal/skill/link"
	"skillatlas/internal/task"
	"skillatlas/internal/task/attempt"
	"skillatlas/internal/testdb"
	"testing"
	"time"
)

func TestExportRoundTripOwnershipAndHistoricalReferences(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	one := account(t, s, "export-one@example.invalid")
	two := account(t, s, "export-two@example.invalid")
	tr := tree(t, s, one.Token, "导出验收")
	a := node(t, s, one.Token, tr.ID, "Go")
	b := node(t, s, one.Token, tr.ID, "数据库")
	unused := node(t, s, one.Token, tr.ID, "临时技能")
	call(t, s, "DELETE", "/v1/skills/"+unused.ID+"?version=1", one.Token, nil, 200)
	edge := link.Input{ID: apiutil.ID(), FromSkillID: a.ID, ToSkillID: b.ID, LinkType: "reference"}
	call(t, s, "POST", "/v1/skill-links", one.Token, edge, 201)
	call(t, s, "DELETE", "/v1/skill-links/"+edge.ID, one.Token, nil, 200)
	item := configuredTask(t, s, one.Token, task.Binding{SkillID: a.ID, RewardLevels: 2})
	for _, seconds := range []int64{20, 50} {
		f := focusInput(a.ID, seconds)
		f.TaskID = &item.ID
		call(t, s, "POST", "/v1/focus-sessions", one.Token, f, 201)
	}
	failed := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(item, "failed"), 201))
	retry := attempt.RetryInput{ID: apiutil.ID(), AttemptNo: 1, Version: failed.Task.Version}
	next := decodeData[task.Task](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/retry", one.Token, retry, 200))
	success := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(next, "success"), 201))
	call(t, s, "POST", "/v1/task-attempts/"+success.Attempt.ID+"/reverse", one.Token, attempt.ReverseInput{ID: apiutil.ID()}, 200)
	job := decodeData[career.Career](t, call(t, s, "POST", "/v1/career-nodes", one.Token, career.Input{Config: state.Config{ID: apiutil.ID(), Name: "开发者", Conditions: levelCondition(a.ID, 1)}, BadgeKey: "code"}, 201))
	call(t, s, "POST", "/v1/career-nodes/"+job.ID+"/transition", one.Token, career.TransitionInput{ID: apiutil.ID(), Version: 1}, 200)
	badge := decodeData[title.Title](t, call(t, s, "POST", "/v1/titles", one.Token, title.Input{Config: state.Config{ID: apiutil.ID(), Name: "起步", Conditions: levelCondition(a.ID, 1)}, IconKey: "star"}, 201))
	call(t, s, "POST", "/v1/titles/"+badge.ID+"/equip", one.Token, title.EquipInput{ID: apiutil.ID(), Version: 1}, 200)
	// 正在本地运行的生命周期可先上传，尚无最终会话也应保留导出。
	call(t, s, "POST", "/v1/activity-events", one.Token, activity.ClientInput{ID: apiutil.ID(), EntityID: apiutil.ID(), SkillID: a.ID, Type: "focus.started", Mode: "count_up", OccurredAt: time.Now().UTC()}, 201)
	d := decodeData[dataexport.Document](t, call(t, s, "GET", "/v1/export", one.Token, nil, 200))
	if err := d.Validate(); err != nil {
		t.Fatal(err)
	}
	if d.Account.ID != one.User.ID || d.Counts["focus_sessions"] != 2 || d.Counts["task_attempts"] != 2 || d.Counts["task_rewards"] != 1 || d.Counts["task_reversals"] != 1 || d.Counts["career_transitions"] != 1 || d.Counts["user_titles"] != 1 || d.Counts["skill_links"] != 1 {
		t.Fatal("导出数量或账号错误")
	}
	data, err := json.MarshalIndent(d, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"password_hash", "token_hash", "request_hash", "create_hash", "result_json", one.Token, two.Token} {
		if bytes.Contains(data, []byte(forbidden)) {
			t.Fatal("导出包含禁止数据")
		}
	}
	path := filepath.Join(t.TempDir(), "skill-atlas-export.json")
	if err = os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	saved, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	roundTrip, err := dataexport.Parse(saved)
	if err != nil || roundTrip.Counts["growth_events"] != 4 {
		t.Fatal("保存后读取或成长来源不一致", err)
	}
	other := decodeData[dataexport.Document](t, call(t, s, "GET", "/v1/export", two.Token, nil, 200))
	if other.Account.ID != two.User.ID || other.Counts["skills"] != 0 || other.Counts["task_attempts"] != 0 {
		t.Fatal("导出跨账号泄漏")
	}
	call(t, s, "GET", "/v1/export?user_id="+one.User.ID, two.Token, nil, 400)
	call(t, s, "GET", "/v1/export", "", nil, 401)
}
