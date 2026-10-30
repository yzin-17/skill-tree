package httpapi

import (
	"skillatlas/internal/apiutil"
	"skillatlas/internal/growth"
	"skillatlas/internal/skill/link"
	"skillatlas/internal/task"
	"skillatlas/internal/task/attempt"
	"skillatlas/internal/testdb"
	"testing"
)

func TestSkillLinksCyclesSoftLockAndRegression(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	one := account(t, s, "links-one@example.invalid")
	two := account(t, s, "links-two@example.invalid")
	x := tree(t, s, one.Token, "开发")
	y := tree(t, s, one.Token, "基础")
	z := tree(t, s, two.Token, "其他账号")
	a := node(t, s, one.Token, x.ID, "A")
	b := node(t, s, one.Token, x.ID, "B")
	c := node(t, s, one.Token, y.ID, "C")
	d := node(t, s, one.Token, y.ID, "D")
	foreign := node(t, s, two.Token, z.ID, "别人技能")
	makeInput := func(from, to, kind string, level int64) link.Input {
		v := link.Input{ID: apiutil.ID(), FromSkillID: from, ToSkillID: to, LinkType: kind}
		if kind == "prerequisite" {
			v.RequiredLevel = &level
		}
		return v
	}
	first := makeInput(a.ID, b.ID, "prerequisite", 2)
	saved := decodeData[link.Link](t, call(t, s, "POST", "/v1/skill-links", one.Token, first, 201))
	call(t, s, "POST", "/v1/skill-links", one.Token, first, 201)
	call(t, s, "POST", "/v1/skill-links", two.Token, first, 404)
	duplicate := first
	duplicate.ID = apiutil.ID()
	call(t, s, "POST", "/v1/skill-links", one.Token, duplicate, 409)
	call(t, s, "POST", "/v1/skill-links", one.Token, makeInput(b.ID, a.ID, "prerequisite", 1), 409)
	for _, pair := range [][2]string{{b.ID, c.ID}, {c.ID, d.ID}} {
		call(t, s, "POST", "/v1/skill-links", one.Token, makeInput(pair[0], pair[1], "prerequisite", 1), 201)
	}
	call(t, s, "POST", "/v1/skill-links", one.Token, makeInput(d.ID, a.ID, "prerequisite", 1), 409)
	call(t, s, "POST", "/v1/skill-links", one.Token, makeInput(d.ID, a.ID, "reference", 0), 201)
	call(t, s, "POST", "/v1/skill-links", one.Token, makeInput(a.ID, a.ID, "reference", 0), 400)
	call(t, s, "POST", "/v1/skill-links", one.Token, makeInput(a.ID, foreign.ID, "reference", 0), 404)
	links := decodeData[[]link.Link](t, call(t, s, "GET", "/v1/skill-links?tree_id="+y.ID, one.Token, nil, 200))
	if len(links) != 3 {
		t.Fatal("跨树关系查询遗漏")
	}
	p := decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+a.ID+"/progress", one.Token, nil, 200))
	if p.Unlocked || len(p.MissingPrerequisites) != 1 || p.MissingPrerequisites[0].CurrentLevel != 1 {
		t.Fatal("软锁缺项错误")
	}
	// 软锁技能允许正常专注；前置成长到等级 2 后解锁，撤销奖励后回退。
	call(t, s, "POST", "/v1/focus-sessions", one.Token, focusInput(a.ID, 60), 201)
	item := configuredTask(t, s, one.Token, task.Binding{SkillID: b.ID, RewardLevels: 1})
	settled := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(item, "success"), 201))
	p = decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+a.ID+"/progress", one.Token, nil, 200))
	if !p.Unlocked || p.TimeXP != 1 {
		t.Fatal("前置等级达标未解锁")
	}
	call(t, s, "POST", "/v1/task-attempts/"+settled.Attempt.ID+"/reverse", one.Token, attempt.ReverseInput{ID: apiutil.ID()}, 200)
	p = decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+a.ID+"/progress", one.Token, nil, 200))
	if p.Unlocked {
		t.Fatal("撤销后前置未回退")
	}
	call(t, s, "PATCH", "/v1/skill-links/"+saved.ID, one.Token, map[string]any{"version": 1, "required_level": 1}, 200)
	call(t, s, "PATCH", "/v1/skill-links/"+saved.ID, one.Token, map[string]any{"version": 1, "required_level": 3}, 409)
	call(t, s, "DELETE", "/v1/skill-links/"+saved.ID, two.Token, nil, 404)
	call(t, s, "DELETE", "/v1/skill-links/"+saved.ID, one.Token, nil, 200)
	call(t, s, "DELETE", "/v1/skill-links/"+saved.ID, one.Token, nil, 200)
	call(t, s, "POST", "/v1/skill-links", one.Token, makeInput(a.ID, b.ID, "prerequisite", 2), 201)
	// 已移除关系仍保留历史引用，删除技能须改用归档。
	call(t, s, "DELETE", "/v1/skills/"+d.ID+"?version=1", one.Token, nil, 409)
}
