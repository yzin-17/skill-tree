package httpapi

import (
	"skillatlas/internal/apiutil"
	"skillatlas/internal/focus"
	"skillatlas/internal/growth"
	"skillatlas/internal/task"
	"skillatlas/internal/testdb"
	"testing"
)

func TestFocusHistoryBindingDoesNotReaward(t *testing.T) {
	s := New(testdb.Open(t))
	owner := account(t, s, "history@example.invalid")
	other := account(t, s, "other-history@example.invalid")
	tr := tree(t, s, owner.Token, "学习")
	sk := node(t, s, owner.Token, tr.ID, "阅读")
	item := decodeData[task.Task](t, call(t, s, "POST", "/v1/tasks", owner.Token, task.Input{ID: apiutil.ID(), Title: "完成阅读", Status: "todo"}, 201))
	for _, seconds := range []int64{1500, 2100} {
		v := focusInput(sk.ID, seconds)
		v.TaskID = &item.ID
		call(t, s, "POST", "/v1/focus-sessions", owner.Token, v, 201)
	}
	page := decodeData[focus.Page](t, call(t, s, "GET", "/v1/focus-sessions?task_id="+item.ID+"&limit=1", owner.Token, nil, 200))
	if page.TotalSeconds != 3600 || page.Count != 2 || len(page.Items) != 1 || page.NextCursor == "" {
		t.Fatal("分页不应改变任务累计")
	}
	next := decodeData[focus.Page](t, call(t, s, "GET", "/v1/focus-sessions?task_id="+item.ID+"&limit=1&cursor="+page.NextCursor, owner.Token, nil, 200))
	if len(next.Items) != 1 || next.Items[0].ID == page.Items[0].ID || next.TotalSeconds != 3600 {
		t.Fatal("续页重复或累计错误")
	}
	free := focusInput(sk.ID, 600)
	original := decodeData[focus.Settlement](t, call(t, s, "POST", "/v1/focus-sessions", owner.Token, free, 201))
	bound := decodeData[focus.Session](t, call(t, s, "PATCH", "/v1/focus-sessions/"+free.ID+"/task", owner.Token, map[string]any{"task_id": item.ID, "version": 1}, 200))
	if bound.SkillID != sk.ID || bound.Version != 2 {
		t.Fatal("绑定改变主技能或版本错误")
	}
	call(t, s, "PATCH", "/v1/focus-sessions/"+free.ID+"/task", owner.Token, map[string]any{"task_id": item.ID, "version": 1}, 200)
	call(t, s, "PATCH", "/v1/focus-sessions/"+free.ID+"/task", owner.Token, map[string]any{"task_id": nil, "version": 1}, 409)
	after := decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+sk.ID+"/progress", owner.Token, nil, 200))
	if after.TotalXP != 70 || after.TotalFocusSeconds != 4200 {
		t.Fatal("重绑重复发 XP")
	}
	replay := decodeData[focus.Settlement](t, call(t, s, "POST", "/v1/focus-sessions", owner.Token, free, 201))
	if replay.AwardedXP != original.AwardedXP || replay.Session.Version != 2 {
		t.Fatal("原始上传重放不应覆盖后续绑定")
	}
	detail := decodeData[task.Task](t, call(t, s, "GET", "/v1/tasks/"+item.ID, owner.Token, nil, 200))
	if detail.TotalFocusSeconds != 4200 || detail.FocusCount != 3 {
		t.Fatal("任务累计与历史不一致")
	}
	call(t, s, "GET", "/v1/focus-sessions/"+free.ID, other.Token, nil, 404)
	empty := decodeData[focus.Page](t, call(t, s, "GET", "/v1/focus-sessions?task_id="+item.ID, other.Token, nil, 200))
	if empty.Count != 0 || len(empty.Items) != 0 {
		t.Fatal("历史跨账号泄露")
	}
	call(t, s, "PATCH", "/v1/focus-sessions/"+free.ID+"/task", owner.Token, map[string]any{"task_id": nil, "version": 2}, 200)
	unbound := decodeData[focus.Page](t, call(t, s, "GET", "/v1/focus-sessions?unbound=true", owner.Token, nil, 200))
	if unbound.Count != 1 || unbound.TotalSeconds != 600 {
		t.Fatal("自由会话筛选错误")
	}
}
