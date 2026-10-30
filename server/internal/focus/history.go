package focus

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/jackc/pgx/v5"
	"net/http"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
	"skillatlas/internal/task"
	"strconv"
	"strings"
	"time"
)

func (s *Service) get(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !apiutil.ValidID(id) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "会话标识无效。"))
		return
	}
	item, err := ByID(r.Context(), s.DB, auth.Current(r.Context()).ID, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			err = apiutil.NotFound()
		}
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, item)
}
func (s *Service) list(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	args := []any{auth.Current(r.Context()).ID}
	conditions := []string{"user_id=$1", "invalidated_at IS NULL"}
	limit := 50
	add := func(clause string, value any) {
		args = append(args, value)
		conditions = append(conditions, fmt.Sprintf(clause, len(args)))
	}
	for _, key := range []string{"skill_id", "task_id"} {
		if value := query.Get(key); value != "" {
			if !apiutil.ValidID(value) {
				apiutil.WriteError(w, apiutil.Fail(400, "invalid_filter", "技能或任务标识无效。"))
				return
			}
			add(key+"=$%d", value)
		}
	}
	if query.Get("unbound") == "true" {
		conditions = append(conditions, "task_id IS NULL")
	}
	for _, key := range []string{"from", "to"} {
		if value := query.Get(key); value != "" {
			at, err := time.Parse(time.RFC3339Nano, value)
			if err != nil {
				apiutil.WriteError(w, apiutil.Fail(400, "invalid_time", "时间筛选无效。"))
				return
			}
			op := ">="
			if key == "to" {
				op = "<"
			}
			add("ended_at"+op+"$%d", at)
		}
	}
	if value := query.Get("limit"); value != "" {
		parsed, err := strconv.Atoi(value)
		if err != nil || parsed < 1 || parsed > 200 {
			apiutil.WriteError(w, apiutil.Fail(400, "invalid_limit", "每页数量必须为 1–200。"))
			return
		}
		limit = parsed
	}
	page := Page{Items: []Session{}}
	if err := s.DB.QueryRow(r.Context(), `SELECT COALESCE(sum(effective_seconds),0),count(*) FROM focus_sessions WHERE `+strings.Join(conditions, " AND "), args...).Scan(&page.TotalSeconds, &page.Count); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if value := query.Get("cursor"); value != "" {
		bytes, err := base64.RawURLEncoding.DecodeString(value)
		parts := strings.Split(string(bytes), "|")
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
		conditions = append(conditions, fmt.Sprintf("(ended_at,id)<($%d,$%d::uuid)", len(args)-1, len(args)))
	}
	args = append(args, limit+1)
	rows, err := s.DB.Query(r.Context(), "SELECT "+columns+" FROM focus_sessions WHERE "+strings.Join(conditions, " AND ")+fmt.Sprintf(" ORDER BY ended_at DESC,id DESC LIMIT $%d", len(args)), args...)
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		item, err := scan(rows)
		if err != nil {
			apiutil.WriteError(w, err)
			return
		}
		page.Items = append(page.Items, item)
	}
	if err = rows.Err(); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if len(page.Items) > limit {
		page.Items = page.Items[:limit]
		last := page.Items[len(page.Items)-1]
		page.NextCursor = base64.RawURLEncoding.EncodeToString([]byte(last.EndedAt.UTC().Format(time.RFC3339Nano) + "|" + last.ID))
	}
	apiutil.Write(w, 200, page)
}
func equalID(a, b *string) bool { return (a == nil && b == nil) || (a != nil && b != nil && *a == *b) }
func (s *Service) bind(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var input struct {
		TaskID  *string `json:"task_id"`
		Version int     `json:"version"`
	}
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if !apiutil.ValidID(id) || input.Version < 1 || (input.TaskID != nil && !apiutil.ValidID(*input.TaskID)) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_binding", "任务标识或版本无效。"))
		return
	}
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		existing, err := ByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		if input.TaskID != nil {
			if _, err = task.ByID(ctx, tx, user.ID, *input.TaskID); err != nil {
				return nil, err
			}
		}
		if equalID(existing.TaskID, input.TaskID) {
			return existing, nil
		}
		if existing.Version != input.Version {
			return nil, apiutil.Fail(409, "version_conflict", "专注关联已更新，请刷新。")
		}
		if _, err = tx.Exec(ctx, `UPDATE focus_sessions SET task_id=$1,version=version+1 WHERE id=$2 AND user_id=$3`, input.TaskID, id, user.ID); err != nil {
			return nil, err
		}
		event := activity.ServerEvent(user.ID, "focus.bound", "focus_session", id, fmt.Sprintf("focus:%s:binding:%d", id, input.Version+1), "调整专注关联", existing.SkillID)
		event.Metadata, _ = json.Marshal(map[string]any{"previous_task_id": existing.TaskID, "task_id": input.TaskID})
		if err = activity.Append(ctx, tx, event); err != nil {
			return nil, err
		}
		return ByID(ctx, tx, user.ID, id)
	})
}
