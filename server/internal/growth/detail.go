package growth

import (
	"errors"
	"github.com/jackc/pgx/v5"
	"net/http"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"time"
)

type EventDetail struct {
	ID              string    `json:"id"`
	SkillID         string    `json:"skill_id"`
	EventType       string    `json:"event_type"`
	SourceID        string    `json:"source_id"`
	DeltaXP         int64     `json:"delta_xp"`
	Note            string    `json:"note"`
	CreatedAt       time.Time `json:"created_at"`
	ReversesEventID *string   `json:"reverses_event_id"`
}

func (s *Service) detail(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !apiutil.ValidID(id) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "流水标识无效。"))
		return
	}
	var value EventDetail
	err := s.DB.QueryRow(r.Context(), `SELECT id::text,skill_id::text,event_type,source_id::text,delta_xp,note,created_at,reverses_event_id::text FROM growth_events WHERE user_id=$1 AND id=$2`, auth.Current(r.Context()).ID, id).Scan(&value.ID, &value.SkillID, &value.EventType, &value.SourceID, &value.DeltaXP, &value.Note, &value.CreatedAt, &value.ReversesEventID)
	if errors.Is(err, pgx.ErrNoRows) {
		err = apiutil.NotFound()
	}
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, value)
}
