package skill

import (
	"encoding/json"
	"os"
	"testing"
)

func TestSkillContractFixtures(t *testing.T) {
	data, err := os.ReadFile("../../contracts/skill.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var contract struct {
		Icons    []string `json:"icons"`
		Fixtures struct {
			Tree  TreeInput  `json:"tree"`
			Skill SkillInput `json:"skill"`
		} `json:"fixtures"`
	}
	if err = json.Unmarshal(data, &contract); err != nil {
		t.Fatal(err)
	}
	if err = contract.Fixtures.Tree.Validate(true); err != nil {
		t.Fatal(err)
	}
	if err = contract.Fixtures.Skill.Validate(true); err != nil {
		t.Fatal(err)
	}
	if len(contract.Icons) != 16 {
		t.Fatal("固定图标库缺失")
	}
	for _, icon := range contract.Icons {
		if !has(Icons, icon) {
			t.Fatal("图标契约漂移")
		}
	}
	invalid := contract.Fixtures.Skill
	invalid.IconKey = "random"
	if invalid.Validate(true) == nil {
		t.Fatal("未知图标被接受")
	}
	invalid = contract.Fixtures.Skill
	invalid.ParentSkillID = &invalid.ID
	if invalid.Validate(true) == nil {
		t.Fatal("允许自身父级")
	}
	invalid = contract.Fixtures.Skill
	invalid.Version = 1
	if invalid.Validate(true) == nil {
		t.Fatal("创建版本错误")
	}
	invalid = contract.Fixtures.Skill
	invalid.Name = "  "
	if invalid.Validate(true) == nil {
		t.Fatal("空名称被接受")
	}
}
