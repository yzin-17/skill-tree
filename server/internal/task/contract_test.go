package task

import (
	"encoding/json"
	"os"
	"testing"
)

func TestTaskContract(t *testing.T) {
	data, err := os.ReadFile("../../contracts/task.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Fixtures struct {
			Task Input `json:"task"`
		} `json:"fixtures"`
	}
	if err = json.Unmarshal(data, &c); err != nil {
		t.Fatal(err)
	}
	if err = c.Fixtures.Task.Validate(true); err != nil {
		t.Fatal(err)
	}
	duplicate := c.Fixtures.Task
	duplicate.Skills = append(duplicate.Skills, duplicate.Skills[0])
	if duplicate.Validate(true) == nil {
		t.Fatal("重复技能未拒绝")
	}
	negative := c.Fixtures.Task
	negative.Skills = []Binding{{SkillID: negative.Skills[0].SkillID, RewardLevels: -1}}
	if negative.Validate(true) == nil {
		t.Fatal("负奖励未拒绝")
	}
	for _, pair := range [][2]string{{"success", "in_progress"}, {"todo", "success"}, {"failed", "in_progress"}, {"canceled", "todo"}} {
		if ValidateEdit(pair[0], pair[1]) == nil {
			t.Fatal("非法状态转换")
		}
	}
	if ValidateEdit("in_progress", "canceled") != nil || ValidateEdit("failed", "failed") != nil {
		t.Fatal("合法编辑被拒绝")
	}
}
