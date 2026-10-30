package httpapi

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"

	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/skill"
	"skillatlas/internal/testdb"
)

func tree(t *testing.T, s *Server, token, name string) skill.Tree {
	return decodeData[skill.Tree](t, call(t, s, "POST", "/v1/skill-trees", token, skill.TreeInput{ID: apiutil.ID(), Name: name, ThemeKey: "blue"}, 201))
}
func node(t *testing.T, s *Server, token, treeID, name string) skill.Skill {
	return decodeData[skill.Skill](t, call(t, s, "POST", "/v1/skills", token, skill.SkillInput{ID: apiutil.ID(), TreeID: treeID, Name: name, IconKey: "code"}, 201))
}
func skillInput(item skill.Skill) skill.SkillInput {
	return skill.SkillInput{ID: item.ID, TreeID: item.TreeID, ParentSkillID: item.ParentSkillID, Name: item.Name, Description: item.Description, IconKey: item.IconKey, SortOrder: item.SortOrder, Archived: item.ArchivedAt != nil, Version: item.Version}
}
func TestSkillTreeRoundTripAndOwnership(t *testing.T) {
	s := New(testdb.Open(t))
	one := account(t, s, "skills-one@example.invalid")
	two := account(t, s, "skills-two@example.invalid")
	data, err := os.ReadFile("../../contracts/skill.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var contract struct {
		Fixtures struct {
			Tree  skill.TreeInput  `json:"tree"`
			Skill skill.SkillInput `json:"skill"`
		} `json:"fixtures"`
	}
	if err = json.Unmarshal(data, &contract); err != nil {
		t.Fatal(err)
	}
	tr := decodeData[skill.Tree](t, call(t, s, "POST", "/v1/skill-trees", one.Token, contract.Fixtures.Tree, 201))
	call(t, s, "POST", "/v1/skill-trees", one.Token, contract.Fixtures.Tree, 201)
	conflict := contract.Fixtures.Tree
	conflict.Name = "不同内容"
	call(t, s, "POST", "/v1/skill-trees", one.Token, conflict, 409)
	call(t, s, "GET", "/v1/skill-trees/"+tr.ID, two.Token, nil, 404)
	sk := decodeData[skill.Skill](t, call(t, s, "POST", "/v1/skills", one.Token, contract.Fixtures.Skill, 201))
	call(t, s, "POST", "/v1/skills", one.Token, contract.Fixtures.Skill, 201)
	call(t, s, "POST", "/v1/skills", two.Token, contract.Fixtures.Skill, 404)
	call(t, s, "GET", "/v1/skills/"+sk.ID, two.Token, nil, 404)
	update := skillInput(sk)
	update.Name = "Go 工程"
	update.IconKey = "terminal"
	update.SortOrder = 4
	updated := decodeData[skill.Skill](t, call(t, s, "PATCH", "/v1/skills/"+sk.ID, one.Token, update, 200))
	if updated.Version != 2 || updated.IconKey != "terminal" || updated.Name != "Go 工程" {
		t.Fatal("技能字段未持久化")
	}
	call(t, s, "PATCH", "/v1/skills/"+sk.ID, one.Token, update, 409)
	second := tree(t, s, one.Token, "计算机基础")
	cross := node(t, s, one.Token, second.ID, "HTTP")
	update = skillInput(updated)
	update.ParentSkillID = &cross.ID
	call(t, s, "PATCH", "/v1/skills/"+sk.ID, one.Token, update, 400)
	childInput := skill.SkillInput{ID: apiutil.ID(), TreeID: tr.ID, ParentSkillID: &sk.ID, Name: "接口", IconKey: "network"}
	child := decodeData[skill.Skill](t, call(t, s, "POST", "/v1/skills", one.Token, childInput, 201))
	grandchildInput := skill.SkillInput{ID: apiutil.ID(), TreeID: tr.ID, ParentSkillID: &child.ID, Name: "鉴权", IconKey: "star"}
	grandchild := decodeData[skill.Skill](t, call(t, s, "POST", "/v1/skills", one.Token, grandchildInput, 201))
	update = skillInput(updated)
	update.ParentSkillID = &grandchild.ID
	call(t, s, "PATCH", "/v1/skills/"+sk.ID, one.Token, update, 400)
	call(t, s, "DELETE", fmt.Sprintf("/v1/skills/%s?version=%d", sk.ID, updated.Version), one.Token, nil, 409)
	archived := skillInput(updated)
	archived.Archived = true
	result := decodeData[skill.Skill](t, call(t, s, "PATCH", "/v1/skills/"+sk.ID, one.Token, archived, 200))
	if result.ArchivedAt == nil {
		t.Fatal("未归档")
	}
	active := decodeData[[]skill.Skill](t, call(t, s, "GET", "/v1/skills?tree_id="+tr.ID, one.Token, nil, 200))
	if len(active) != 2 {
		t.Fatal("归档筛选错误")
	}
	call(t, s, "GET", "/v1/skills/"+sk.ID, one.Token, nil, 200)
	fresh := node(t, s, one.Token, tr.ID, "可删除")
	call(t, s, "DELETE", "/v1/skills/"+fresh.ID+"?version=2", one.Token, nil, 409)
	call(t, s, "DELETE", "/v1/skills/"+fresh.ID+"?version=1", two.Token, nil, 404)
	call(t, s, "DELETE", "/v1/skills/"+fresh.ID+"?version=1", one.Token, nil, 200)
	call(t, s, "GET", "/v1/skills/"+fresh.ID, one.Token, nil, 404)
	history := decodeData[activity.Page](t, call(t, s, "GET", "/v1/activity-events?skill_id="+fresh.ID, one.Token, nil, 200))
	if len(history.Items) != 2 {
		t.Fatal("删除应保留创建和删除事件")
	}
	treeUpdate := skill.TreeInput{ID: tr.ID, Name: "后端进阶", Description: "持久化", ThemeKey: "gold", SortOrder: 3, Archived: true, Version: tr.Version}
	edited := decodeData[skill.Tree](t, call(t, s, "PATCH", "/v1/skill-trees/"+tr.ID, one.Token, treeUpdate, 200))
	if edited.ArchivedAt == nil || edited.ThemeKey != "gold" || edited.SortOrder != 3 {
		t.Fatal("树编辑字段未保存")
	}
	hidden := decodeData[[]skill.Skill](t, call(t, s, "GET", "/v1/skills?tree_id="+tr.ID, one.Token, nil, 200))
	if len(hidden) != 0 {
		t.Fatal("归档树下技能默认应隐藏")
	}
	all := decodeData[[]skill.Skill](t, call(t, s, "GET", "/v1/skills?include_archived=true&tree_id="+tr.ID, one.Token, nil, 200))
	if len(all) != 3 {
		t.Fatal("归档记录应保留")
	}
	blocked := skill.SkillInput{ID: apiutil.ID(), TreeID: tr.ID, Name: "不可新建", IconKey: "code"}
	call(t, s, "POST", "/v1/skills", one.Token, blocked, 409)
}
