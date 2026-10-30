package httpapi

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/testdb"
)

func account(t *testing.T, s *Server, email string) auth.Session {
	return decodeData[auth.Session](t, call(t, s, "POST", "/v1/auth/register", "", auth.Credentials{Email: email, Password: "SkillAtlas-test-only-2026", Timezone: "Asia/Shanghai"}, 201))
}

func TestActivityAtomicityOrderingOwnership(t *testing.T) {
	db := testdb.Open(t)
	s := New(db)
	ctx := context.Background()
	one := account(t, s, "events-one@example.invalid")
	two := account(t, s, "events-two@example.invalid")
	fixture, err := os.ReadFile("../../contracts/activity.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var contract struct {
		Producers map[string][]string `json:"producers"`
	}
	if err = json.Unmarshal(fixture, &contract); err != nil {
		t.Fatal(err)
	}
	if len(contract.Producers["client"]) != 4 {
		t.Fatal("客户端事件责任缺失")
	}
	skill := apiutil.ID()
	at := time.Date(2026, 10, 29, 0, 0, 0, 0, time.UTC)
	for i := range 3 {
		tx, err := db.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		event := activity.ServerEvent(one.User.ID, "skill.created", "skill", skill, "fixture:"+apiutil.ID(), "创建技能", skill)
		event.OccurredAt = at.Add(time.Duration(i) * time.Second)
		if err = activity.Append(ctx, tx, event); err != nil {
			t.Fatal(err)
		}
		if i == 2 {
			tx.Rollback(ctx)
		} else if err = tx.Commit(ctx); err != nil {
			t.Fatal(err)
		}
	}
	page := decodeData[activity.Page](t, call(t, s, "GET", "/v1/activity-events?limit=1&skill_id="+skill, one.Token, nil, 200))
	if len(page.Items) != 1 || !page.Items[0].OccurredAt.Equal(at.Add(time.Second)) || page.NextCursor == "" {
		t.Fatalf("分页或时间错误: %+v", page)
	}
	next := decodeData[activity.Page](t, call(t, s, "GET", "/v1/activity-events?limit=1&cursor="+page.NextCursor, one.Token, nil, 200))
	if len(next.Items) != 1 || next.Items[0].ID == page.Items[0].ID || next.NextCursor != "" {
		t.Fatal("游标遗漏或重复")
	}
	other := decodeData[activity.Page](t, call(t, s, "GET", "/v1/activity-events?skill_id="+skill, two.Token, nil, 200))
	if len(other.Items) != 0 {
		t.Fatal("事件跨账号泄露")
	}
	call(t, s, "GET", "/v1/activity-events?cursor=invalid", one.Token, nil, 400)
	call(t, s, "GET", "/v1/activity-events?from=invalid", one.Token, nil, 400)
	call(t, s, "GET", "/v1/activity-events?limit=0", one.Token, nil, 400)
	var count int
	if err = db.QueryRow(ctx, `SELECT count(*) FROM activity_events WHERE user_id=$1`, one.User.ID).Scan(&count); err != nil || count != 2 {
		t.Fatal("回滚未保持事件原子性")
	}
	tx, err := db.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	e := activity.ServerEvent(one.User.ID, "skill.created", "skill", skill, "same-source", "创建技能")
	if err = activity.Append(ctx, tx, e); err != nil {
		t.Fatal(err)
	}
	if err = activity.Append(ctx, tx, e); err == nil {
		t.Fatal("重复来源应拒绝")
	}
}
