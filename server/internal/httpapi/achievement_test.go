package httpapi

import (
	"context"
	"fmt"
	"skillatlas/internal/achievement/career"
	"skillatlas/internal/achievement/conditions"
	"skillatlas/internal/achievement/state"
	"skillatlas/internal/achievement/title"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/growth"
	"skillatlas/internal/task"
	"skillatlas/internal/task/attempt"
	"skillatlas/internal/testdb"
	"testing"
)

func levelCondition(skill string, level int64) conditions.Set {
	return conditions.Set{All: []conditions.Condition{{Type: "skill_level", SkillID: &skill, GTE: &level}}}
}
func TestAchievementEvidenceTransitionsEquipAndRegression(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	ctx := context.Background()
	one := account(t, s, "achievement@example.invalid")
	two := account(t, s, "achievement-other@example.invalid")
	aTree := tree(t, s, one.Token, "开发")
	bTree := tree(t, s, one.Token, "基础")
	a := node(t, s, one.Token, aTree.ID, "Go")
	b := node(t, s, one.Token, bTree.ID, "数据库")
	empty := decodeData[title.Catalog](t, call(t, s, "GET", "/v1/titles", one.Token, nil, 200))
	if len(empty.Items) != 0 {
		t.Fatal("不应自动植入称号")
	}
	item := configuredTask(t, s, one.Token, task.Binding{SkillID: a.ID, RewardLevels: 1})
	all := conditions.Set{All: []conditions.Condition{{Type: "skill_level", SkillID: &a.ID, GTE: new(int64(2))}, {Type: "focus_minutes", SkillID: &b.ID, GTE: new(int64(60))}, {Type: "task_success_count", GTE: new(int64(1))}, {Type: "specific_task_success", TaskID: &item.ID}}}
	baseInput := career.Input{Config: state.Config{ID: apiutil.ID(), Name: "开发学徒", Conditions: levelCondition(a.ID, 1)}, BadgeKey: "compass"}
	base := decodeData[career.Career](t, call(t, s, "POST", "/v1/career-nodes", one.Token, baseInput, 201))
	branchInput := career.Input{Config: state.Config{ID: apiutil.ID(), Name: "全栈开发者", Conditions: all}, BadgeKey: "code", ParentCareerID: &base.ID}
	branch := decodeData[career.Career](t, call(t, s, "POST", "/v1/career-nodes", one.Token, branchInput, 201))
	badgeInput := title.Input{Config: state.Config{ID: apiutil.ID(), Name: "第一次突破", Conditions: all}, IconKey: "star"}
	badge := decodeData[title.Title](t, call(t, s, "POST", "/v1/titles", one.Token, badgeInput, 201))
	if badge.Evaluation.Eligible || badge.UnlockedAt != nil {
		t.Fatal("未达标称号提前解锁")
	}
	call(t, s, "POST", "/v1/titles", one.Token, badgeInput, 201)
	call(t, s, "POST", "/v1/titles", two.Token, badgeInput, 404)
	foreign := badgeInput
	foreign.ID = apiutil.ID()
	call(t, s, "POST", "/v1/titles", two.Token, foreign, 404)
	cycle := baseInput
	cycle.Version = base.Version
	cycle.ParentCareerID = &branch.ID
	call(t, s, "PATCH", "/v1/career-nodes/"+base.ID, one.Token, cycle, 409)
	call(t, s, "POST", "/v1/titles/"+badge.ID+"/equip", one.Token, title.EquipInput{ID: apiutil.ID(), Version: 1}, 409)
	before := decodeData[career.Catalog](t, call(t, s, "GET", "/v1/career-nodes", one.Token, nil, 200))
	if before.CurrentCareerID != nil || len(before.History) != 0 {
		t.Fatal("条件达标不应自动转职")
	}
	rootCommand := career.TransitionInput{ID: apiutil.ID(), Version: 1}
	rootResult := decodeData[career.Catalog](t, call(t, s, "POST", "/v1/career-nodes/"+base.ID+"/transition", one.Token, rootCommand, 200))
	if rootResult.CurrentCareerID == nil || *rootResult.CurrentCareerID != base.ID {
		t.Fatal("手动转职未保存")
	}
	call(t, s, "POST", "/v1/career-nodes/"+base.ID+"/transition", one.Token, rootCommand, 200)
	call(t, s, "POST", "/v1/career-nodes/"+branch.ID+"/transition", one.Token, career.TransitionInput{ID: apiutil.ID(), Version: 1, FromCareerID: &base.ID}, 409)
	manual := focusInput(b.ID, 3600)
	manual.Mode = "manual"
	manual.Source = "manual"
	call(t, s, "POST", "/v1/focus-sessions", one.Token, manual, 201)
	afterManual := decodeData[title.Catalog](t, call(t, s, "GET", "/v1/titles", one.Token, nil, 200))
	if afterManual.Items[0].Evaluation.Evidence[1].Current != 0 {
		t.Fatal("补录进入真实时长条件")
	}
	real := focusInput(b.ID, 3600)
	call(t, s, "POST", "/v1/focus-sessions", one.Token, real, 201)
	// 解锁日志写入失败必须回滚触发它的整笔任务奖励。
	_, err := db.Exec(ctx, fmt.Sprintf(`CREATE FUNCTION reject_unlock() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.type='title.unlocked' AND NEW.entity_id='%s'::uuid THEN RAISE EXCEPTION '隔离解锁故障'; END IF; RETURN NEW; END $$;CREATE TRIGGER reject_unlock BEFORE INSERT ON activity_events FOR EACH ROW EXECUTE FUNCTION reject_unlock();`, badge.ID))
	if err != nil {
		t.Fatal(err)
	}
	conclusion := concludeInput(item, "success")
	call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, conclusion, 500)
	unchanged := decodeData[growth.Progress](t, call(t, s, "GET", "/v1/skills/"+a.ID+"/progress", one.Token, nil, 200))
	if unchanged.TotalXP != 0 {
		t.Fatal("成就故障未回滚奖励")
	}
	if _, err = db.Exec(ctx, `DROP TRIGGER reject_unlock ON activity_events;DROP FUNCTION reject_unlock()`); err != nil {
		t.Fatal(err)
	}
	settled := decodeData[attempt.Settlement](t, call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, conclusion, 201))
	eligible := decodeData[title.Catalog](t, call(t, s, "GET", "/v1/titles", one.Token, nil, 200))
	entry := eligible.Items[0]
	if !entry.Evaluation.Eligible || entry.UnlockedAt == nil || entry.UnlockedEvidence == nil || len(entry.Evaluation.Evidence[1].SourceIDs) != 1 || entry.Evaluation.Evidence[1].SourceIDs[0] != real.ID {
		t.Fatal("四类求值或真实来源证据错误")
	}
	equip := title.EquipInput{ID: apiutil.ID(), Version: 1}
	equipped := decodeData[title.Catalog](t, call(t, s, "POST", "/v1/titles/"+badge.ID+"/equip", one.Token, equip, 200))
	if equipped.EquippedTitleID == nil || *equipped.EquippedTitleID != badge.ID {
		t.Fatal("佩戴未保存")
	}
	call(t, s, "POST", "/v1/titles/"+badge.ID+"/equip", one.Token, equip, 200)
	branchCommand := career.TransitionInput{ID: apiutil.ID(), Version: 1, FromCareerID: &base.ID}
	call(t, s, "POST", "/v1/career-nodes/"+branch.ID+"/transition", one.Token, branchCommand, 200)
	call(t, s, "POST", "/v1/career-nodes/"+branch.ID+"/transition", one.Token, branchCommand, 200)
	call(t, s, "POST", "/v1/task-attempts/"+settled.Attempt.ID+"/reverse", one.Token, attempt.ReverseInput{ID: apiutil.ID()}, 200)
	regressed := decodeData[title.Catalog](t, call(t, s, "GET", "/v1/titles", one.Token, nil, 200))
	if regressed.EquippedTitleID != nil || regressed.Items[0].UnlockedAt == nil || regressed.Items[0].Evaluation.Eligible || !regressed.Items[0].UnlockedEvidence.Eligible {
		t.Fatal("回退未保留解锁或未取消佩戴")
	}
	call(t, s, "POST", "/v1/titles/"+badge.ID+"/equip", one.Token, title.EquipInput{ID: apiutil.ID(), Version: 1}, 409)
	careers := decodeData[career.Catalog](t, call(t, s, "GET", "/v1/career-nodes", one.Token, nil, 200))
	if careers.CurrentCareerID == nil || *careers.CurrentCareerID != branch.ID || len(careers.History) != 2 {
		t.Fatal("条件回退不应删除职业历史或当前职业")
	}
	current := decodeData[task.Task](t, call(t, s, "GET", "/v1/tasks/"+item.ID, one.Token, nil, 200))
	call(t, s, "POST", "/v1/tasks/"+item.ID+"/attempts", one.Token, concludeInput(current, "success"), 201)
	call(t, s, "POST", "/v1/titles/"+badge.ID+"/equip", one.Token, title.EquipInput{ID: apiutil.ID(), Version: 1}, 200)
	secondInput := title.Input{Config: state.Config{ID: apiutil.ID(), Name: "重新出发", Conditions: levelCondition(a.ID, 1)}, IconKey: "leaf"}
	second := decodeData[title.Title](t, call(t, s, "POST", "/v1/titles", one.Token, secondInput, 201))
	switchResult := decodeData[title.Catalog](t, call(t, s, "POST", "/v1/titles/"+second.ID+"/equip", one.Token, title.EquipInput{ID: apiutil.ID(), Version: 1}, 200))
	worn := 0
	for _, v := range switchResult.Items {
		if v.EquippedAt != nil {
			worn++
		}
	}
	if worn != 1 {
		t.Fatal("同时佩戴多个称号")
	}
	edit := secondInput
	edit.Version = 1
	edit.Conditions = levelCondition(a.ID, 99)
	call(t, s, "PATCH", "/v1/titles/"+second.ID, one.Token, edit, 200)
	afterEdit := decodeData[title.Catalog](t, call(t, s, "GET", "/v1/titles", one.Token, nil, 200))
	if afterEdit.EquippedTitleID != nil {
		t.Fatal("修改条件未取消失效佩戴")
	}
	var unlocks int
	if err = db.QueryRow(ctx, `SELECT count(*) FROM activity_events WHERE user_id=$1 AND type='title.unlocked' AND entity_id=$2`, one.User.ID, badge.ID).Scan(&unlocks); err != nil || unlocks != 1 {
		t.Fatal("重新达标重复解锁")
	}
	otherCatalog := decodeData[title.Catalog](t, call(t, s, "GET", "/v1/titles", two.Token, nil, 200))
	if len(otherCatalog.Items) != 0 {
		t.Fatal("称号跨账号泄漏")
	}
}
