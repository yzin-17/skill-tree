package link

import (
	"encoding/json"
	"os"
	"testing"
)

func TestLinkContract(t *testing.T) {
	data, err := os.ReadFile("../../../contracts/skill-link.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Fixtures []Input `json:"fixtures"`
	}
	if err = json.Unmarshal(data, &c); err != nil {
		t.Fatal(err)
	}
	for _, v := range c.Fixtures {
		if err = v.Validate(); err != nil {
			t.Fatal(err)
		}
	}
	bad := c.Fixtures[0]
	bad.ToSkillID = bad.FromSkillID
	if bad.Validate() == nil {
		t.Fatal("自引用未拒绝")
	}
	bad = c.Fixtures[1]
	bad.RequiredLevel = new(int64(2))
	if bad.Validate() == nil {
		t.Fatal("普通关联不应设置阈值")
	}
}
