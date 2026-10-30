package httpapi

import (
	"context"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/task"
	"skillatlas/internal/testdb"
	"testing"
	"time"
)

func taskInput(item task.Task) task.Input {
	return task.Input{ID: item.ID, Title: item.Title, Description: item.Description, SuccessCriteria: item.SuccessCriteria, Status: item.Status, DueAt: item.DueAt, Pinned: item.Pinned, Skills: item.Skills, Version: item.Version}
}
func TestTaskBindingsCancelAndAtomicity(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	owner := account(t, s, "tasks@example.invalid")
	other := account(t, s, "other-tasks@example.invalid")
	tr := tree(t, s, owner.Token, "后端")
	one := node(t, s, owner.Token, tr.ID, "Go")
	two := node(t, s, owner.Token, tr.ID, "SQL")
	foreignTree := tree(t, s, other.Token, "其他")
	foreign := node(t, s, other.Token, foreignTree.ID, "其他技能")
	past := time.Now().Add(-24 * time.Hour)
	input := task.Input{ID: apiutil.ID(), Title: "登录接口", Description: "实现接口", SuccessCriteria: "错误可见", Status: "todo", DueAt: &past, Pinned: true, Skills: []task.Binding{{SkillID: one.ID, RewardLevels: 2}, {SkillID: two.ID, RewardLevels: 0}}}
	created := decodeData[task.Task](t, call(t, s, "POST", "/v1/tasks", owner.Token, input, 201))
	if created.Status != "todo" || len(created.Skills) != 2 || !created.Pinned {
		t.Fatal("任务配置错误或到期自动结算")
	}
	call(t, s, "POST", "/v1/tasks", owner.Token, input, 201)
	call(t, s, "GET", "/v1/tasks/"+created.ID, other.Token, nil, 404)
	failed := input
	failed.ID = apiutil.ID()
	failed.Skills = []task.Binding{{SkillID: one.ID, RewardLevels: 2}, {SkillID: foreign.ID, RewardLevels: 1}}
	call(t, s, "POST", "/v1/tasks", owner.Token, failed, 404)
	var count int
	if err := db.QueryRow(context.Background(), `SELECT count(*) FROM tasks WHERE id=$1`, failed.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("越权失败留下部分任务")
	}
	duplicate := input
	duplicate.ID = apiutil.ID()
	duplicate.Skills = []task.Binding{{SkillID: one.ID, RewardLevels: 2}, {SkillID: one.ID, RewardLevels: 1}}
	call(t, s, "POST", "/v1/tasks", owner.Token, duplicate, 400)
	update := taskInput(created)
	update.Status = "success"
	call(t, s, "PATCH", "/v1/tasks/"+created.ID, owner.Token, update, 409)
	update.Status = "in_progress"
	progress := decodeData[task.Task](t, call(t, s, "PATCH", "/v1/tasks/"+created.ID, owner.Token, update, 200))
	call(t, s, "PATCH", "/v1/tasks/"+created.ID, owner.Token, update, 409)
	update = taskInput(progress)
	update.Status = "canceled"
	canceled := decodeData[task.Task](t, call(t, s, "PATCH", "/v1/tasks/"+created.ID, owner.Token, update, 200))
	if canceled.Status != "canceled" || canceled.CurrentAttemptNo != 1 {
		t.Fatal("取消不应生成新尝试")
	}
	call(t, s, "DELETE", "/v1/skills/"+one.ID+"?version=1", owner.Token, nil, 409)
	archived := skillInput(one)
	archived.Archived = true
	call(t, s, "PATCH", "/v1/skills/"+one.ID, owner.Token, archived, 200)
	update = taskInput(canceled)
	update.Title = "已取消但保留历史"
	call(t, s, "PATCH", "/v1/tasks/"+created.ID, owner.Token, update, 200)
	list := decodeData[[]task.Task](t, call(t, s, "GET", "/v1/tasks?skill_id="+one.ID, owner.Token, nil, 200))
	if len(list) != 1 {
		t.Fatal("多技能筛选重复或丢失")
	}
}
