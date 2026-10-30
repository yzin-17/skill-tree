package activity

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
)

type Event struct {
	ID         string          `json:"id"`
	UserID     string          `json:"-"`
	Type       string          `json:"type"`
	Producer   string          `json:"producer"`
	EntityType string          `json:"entity_type"`
	EntityID   string          `json:"entity_id"`
	SourceKey  string          `json:"-"`
	Summary    string          `json:"summary"`
	SkillIDs   []string        `json:"skill_ids"`
	Metadata   json.RawMessage `json:"metadata"`
	OccurredAt time.Time       `json:"occurred_at"`
	CreatedAt  time.Time       `json:"created_at"`
}
type Page struct {
	Items      []Event `json:"items"`
	NextCursor string  `json:"next_cursor"`
}
type Service struct{ DB *pgxpool.Pool }

func (s *Service) Register(mux *http.ServeMux, identity *auth.Service) {
	mux.HandleFunc("GET /v1/activity-events", identity.Require(s.list))
	mux.HandleFunc("POST /v1/activity-events", identity.Require(s.upload))
}

func Append(ctx context.Context, tx pgx.Tx, event Event) error {
	if event.ID == "" {
		event.ID = apiutil.ID()
	}
	if event.Producer == "" {
		event.Producer = "server"
	}
	if event.Metadata == nil {
		event.Metadata = json.RawMessage(`{}`)
	}
	if event.SkillIDs == nil {
		event.SkillIDs = []string{}
	}
	if event.OccurredAt.IsZero() {
		event.OccurredAt = time.Now().UTC()
	}
	_, err := tx.Exec(ctx, `INSERT INTO activity_events(id,user_id,type,producer,entity_type,entity_id,source_key,summary,skill_ids,metadata,occurred_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`, event.ID, event.UserID, event.Type, event.Producer, event.EntityType, event.EntityID, event.SourceKey, event.Summary, event.SkillIDs, event.Metadata, event.OccurredAt)
	return err
}
func ServerEvent(user, kind, entity, id, source, summary string, skills ...string) Event {
	return Event{UserID: user, Type: kind, EntityType: entity, EntityID: id, SourceKey: source, Summary: summary, SkillIDs: skills}
}
func cursor(event Event) string {
	return base64.RawURLEncoding.EncodeToString([]byte(event.OccurredAt.UTC().Format(time.RFC3339Nano) + "|" + event.ID))
}

func (s *Service) list(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	args := []any{auth.Current(r.Context()).ID}
	where := []string{"user_id=$1"}
	add := func(clause string, value any) {
		args = append(args, value)
		where = append(where, fmt.Sprintf(clause, len(args)))
	}
	limit := 50
	if value := query.Get("limit"); value != "" {
		parsed, err := strconv.Atoi(value)
		if err != nil || parsed < 1 || parsed > 200 {
			apiutil.WriteError(w, apiutil.Fail(400, "invalid_limit", "每页数量必须为 1–200。"))
			return
		}
		limit = parsed
	}
	if kind := query.Get("type"); kind != "" {
		add("type=$%d", kind)
	}
	if skill := query.Get("skill_id"); skill != "" {
		if !apiutil.ValidID(skill) {
			apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "技能标识无效。"))
			return
		}
		add("skill_ids @> ARRAY[$%d]::uuid[]", skill)
	}
	for _, key := range []string{"from", "to"} {
		if value := query.Get(key); value != "" {
			parsed, err := time.Parse(time.RFC3339Nano, value)
			if err != nil {
				apiutil.WriteError(w, apiutil.Fail(400, "invalid_time", "时间必须为 RFC3339 格式。"))
				return
			}
			op := ">="
			if key == "to" {
				op = "<"
			}
			add("occurred_at"+op+"$%d", parsed)
		}
	}
	if value := query.Get("cursor"); value != "" {
		decoded, err := base64.RawURLEncoding.DecodeString(value)
		parts := strings.Split(string(decoded), "|")
		if err != nil || len(parts) != 2 || !apiutil.ValidID(parts[1]) {
			apiutil.WriteError(w, apiutil.Fail(400, "invalid_cursor", "分页游标无效。"))
			return
		}
		at, err := time.Parse(time.RFC3339Nano, parts[0])
		if err != nil {
			apiutil.WriteError(w, apiutil.Fail(400, "invalid_cursor", "分页游标无效。"))
			return
		}
		args = append(args, at, parts[1])
		where = append(where, fmt.Sprintf("(occurred_at,id)<($%d,$%d::uuid)", len(args)-1, len(args)))
	}
	args = append(args, limit+1)
	rows, err := s.DB.Query(r.Context(), `SELECT id::text,type,producer,entity_type,entity_id::text,summary,skill_ids::text[],metadata,occurred_at,created_at FROM activity_events WHERE `+strings.Join(where, " AND ")+fmt.Sprintf(" ORDER BY occurred_at DESC,id DESC LIMIT $%d", len(args)), args...)
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	defer rows.Close()
	page := Page{Items: []Event{}}
	for rows.Next() {
		var event Event
		if err = rows.Scan(&event.ID, &event.Type, &event.Producer, &event.EntityType, &event.EntityID, &event.Summary, &event.SkillIDs, &event.Metadata, &event.OccurredAt, &event.CreatedAt); err != nil {
			apiutil.WriteError(w, err)
			return
		}
		page.Items = append(page.Items, event)
	}
	if err = rows.Err(); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if len(page.Items) > limit {
		page.Items = page.Items[:limit]
		page.NextCursor = cursor(page.Items[len(page.Items)-1])
	}
	apiutil.Write(w, 200, page)
}
