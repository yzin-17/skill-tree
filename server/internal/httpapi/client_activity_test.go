package httpapi

import (
	"context"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/focus"
	"skillatlas/internal/testdb"
	"sync"
	"testing"
	"time"
)

func TestClientActivityReplayReferencesAndFinalSession(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	ctx := context.Background()
	one := account(t, s, "client-one@example.invalid")
	two := account(t, s, "client-two@example.invalid")
	tr := tree(t, s, one.Token, "事件验收")
	sk := node(t, s, one.Token, tr.ID, "计时")
	tr2 := tree(t, s, two.Token, "另一账号")
	sk2 := node(t, s, two.Token, tr2.ID, "另一技能")
	input := activity.ClientInput{ID: apiutil.ID(), Type: "focus.started", EntityID: apiutil.ID(), SkillID: sk.ID, OccurredAt: time.Now().UTC(), Mode: "count_up"}
	first := decodeData[activity.Event](t, call(t, s, "POST", "/v1/activity-events", one.Token, input, 201))
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			replay := decodeData[activity.Event](t, call(t, s, "POST", "/v1/activity-events", one.Token, input, 201))
			if replay.ID != first.ID || !replay.CreatedAt.Equal(first.CreatedAt) {
				t.Error("重放未返回原事件")
			}
		}()
	}
	wg.Wait()
	changed := input
	changed.EffectiveSeconds = 1
	call(t, s, "POST", "/v1/activity-events", one.Token, changed, 409)
	call(t, s, "POST", "/v1/activity-events", two.Token, input, 404)
	changed.ID = apiutil.ID()
	changed.SkillID = sk2.ID
	call(t, s, "POST", "/v1/activity-events", one.Token, changed, 404)
	changed.SkillID = sk.ID
	changed.Type = "growth.accrued"
	call(t, s, "POST", "/v1/activity-events", one.Token, changed, 400)
	foreign := focusInput(sk2.ID, 60)
	foreign.ID = input.EntityID
	call(t, s, "POST", "/v1/focus-sessions", two.Token, foreign, 404)
	final := focusInput(sk.ID, 70)
	final.ID = input.EntityID
	wrong := final
	wrong.Mode = "countdown"
	target := int64(100)
	wrong.TargetSeconds = &target
	call(t, s, "POST", "/v1/focus-sessions", one.Token, wrong, 409)
	settled := decodeData[focus.Settlement](t, call(t, s, "POST", "/v1/focus-sessions", one.Token, final, 201))
	if settled.AwardedXP != 1 {
		t.Fatal("生命周期事件不应改变经验")
	}
	ended := input
	ended.ID = apiutil.ID()
	ended.Type = "focus.ended"
	ended.EffectiveSeconds = 70
	ended.OccurredAt = final.EndedAt
	call(t, s, "POST", "/v1/activity-events", one.Token, ended, 201)
	call(t, s, "POST", "/v1/activity-events", one.Token, ended, 201)
	other := ended
	other.ID = apiutil.ID()
	other.SkillID = sk2.ID
	call(t, s, "POST", "/v1/activity-events", two.Token, other, 404)
	var count int
	if err := db.QueryRow(ctx, `SELECT count(*) FROM activity_events WHERE user_id=$1 AND producer='client'`, one.User.ID).Scan(&count); err != nil || count != 2 {
		t.Fatal("客户端事件重复或丢失", err, count)
	}
	// 最终会话先到时，后续生命周期仍可补交；未知任务不能混入。
	second := focusInput(sk.ID, 20)
	call(t, s, "POST", "/v1/focus-sessions", one.Token, second, 201)
	late := input
	late.ID = apiutil.ID()
	late.EntityID = second.ID
	late.TaskID = new(apiutil.ID())
	call(t, s, "POST", "/v1/activity-events", one.Token, late, 404)
	late.TaskID = nil
	call(t, s, "POST", "/v1/activity-events", one.Token, late, 201)
}
