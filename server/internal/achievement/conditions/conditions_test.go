package conditions

import (
	"encoding/json"
	"os"
	"testing"
)

func TestAchievementConditionContract(t *testing.T) {
	data, err := os.ReadFile("../../../contracts/achievement.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Fixtures struct {
			Conditions Set     `json:"conditions"`
			Values     []int64 `json:"values"`
		} `json:"fixtures"`
	}
	if err = json.Unmarshal(data, &c); err != nil {
		t.Fatal(err)
	}
	facts := []Fact{}
	for _, v := range c.Fixtures.Values {
		facts = append(facts, Fact{Current: v})
	}
	result, err := Evaluate(c.Fixtures.Conditions, facts)
	if err != nil || !result.Eligible || len(result.Evidence) != 4 {
		t.Fatal("四类全部满足求值错误", err)
	}
	for i := range facts {
		saved := facts[i].Current
		facts[i].Current = 0
		result, err = Evaluate(c.Fixtures.Conditions, facts)
		if err != nil || result.Eligible || result.Evidence[i].Met {
			t.Fatal("缺项未拒绝", err)
		}
		facts[i].Current = saved
	}
	bad := Set{All: append([]Condition{}, c.Fixtures.Conditions.All...)}
	bad.All = append(bad.All, bad.All[0])
	if bad.Validate() == nil {
		t.Fatal("重复条件未拒绝")
	}
	bad = Set{All: []Condition{{Type: "arbitrary_code"}}}
	if bad.Validate() == nil {
		t.Fatal("非法表达式未拒绝")
	}
	if (Set{}).Validate() == nil {
		t.Fatal("空条件未拒绝")
	}
}
