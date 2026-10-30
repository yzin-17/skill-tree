package attempt

import (
	"errors"
	"github.com/jackc/pgx/v5"
	"net/http"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"time"
)

type RetryDetail struct {
	ID                string    `json:"id"`
	TaskID            string    `json:"task_id"`
	PreviousAttemptNo int       `json:"previous_attempt_no"`
	NextAttemptNo     int       `json:"next_attempt_no"`
	PreviousAttemptID string    `json:"previous_attempt_id"`
	CreatedAt         time.Time `json:"created_at"`
}

func (s *Service) retryDetail(w http.ResponseWriter, r *http.Request) {
	if !validPath(w, r) {
		return
	}
	var value RetryDetail
	err := s.DB.QueryRow(r.Context(), `SELECT q.id::text,q.task_id::text,q.previous_attempt_no,q.next_attempt_no,a.id::text,q.created_at FROM task_retry_requests q JOIN task_attempts a ON a.task_id=q.task_id AND a.attempt_no=q.previous_attempt_no AND a.user_id=q.user_id WHERE q.user_id=$1 AND q.id=$2`, auth.Current(r.Context()).ID, r.PathValue("id")).Scan(&value.ID, &value.TaskID, &value.PreviousAttemptNo, &value.NextAttemptNo, &value.PreviousAttemptID, &value.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		err = apiutil.NotFound()
	}
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, value)
}
