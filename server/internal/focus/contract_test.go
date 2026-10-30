package focus

import (
	"encoding/json"
	"os"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/growth"
	"testing"
	"time"
)

func TestFocusContract(t *testing.T) {
	data, err := os.ReadFile("../../contracts/focus.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Fixtures struct {
			Seconds []struct{ Before, Added, Awarded int64 }
			Levels  []struct {
				TimeXP      int64 `json:"time_xp"`
				TaskBonusXP int64 `json:"task_bonus_xp"`
				TotalXP     int64 `json:"total_xp"`
				Level       int64
				XPCurrent   int64 `json:"xp_current"`
			}
		} `json:"fixtures"`
	}
	if err = json.Unmarshal(data, &c); err != nil {
		t.Fatal(err)
	}
	for _, x := range c.Fixtures.Seconds {
		if growth.FocusXP(x.Before, x.Added) != x.Awarded {
			t.Fatal("累计秒数取整错误")
		}
	}
	for _, x := range c.Fixtures.Levels {
		p := growth.Calculate("", 2400, x.TimeXP, x.TaskBonusXP)
		if p.TotalXP != x.TotalXP || p.Level != x.Level || p.XPCurrent != x.XPCurrent {
			t.Fatal("等级公式错误")
		}
	}
	v := Input{ID: apiutil.ID(), SkillID: apiutil.ID(), Mode: "count_up", Source: "timer", EffectiveSeconds: 70, StartedAt: time.Now(), EndedAt: time.Now().Add(-time.Hour)}
	if err = v.Validate(); err != nil {
		t.Fatal("单调计时不能被墙上时钟回调改写")
	}
	v.Mode = "manual"
	v.Source = "manual"
	if v.Validate() == nil {
		t.Fatal("补录区间无效应拒绝")
	}
	v.Mode = "countdown"
	v.Source = "timer"
	target := int64(60)
	v.TargetSeconds = &target
	if v.Validate() == nil {
		t.Fatal("倒计时不可超过目标")
	}
}
