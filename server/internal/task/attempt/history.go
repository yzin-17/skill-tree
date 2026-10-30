package attempt

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5"
	"net/http"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/skill"
	"skillatlas/internal/task"
)

func Details(ctx context.Context, q skill.Queryer, user, id string) (Detail, error) {
	item, err := ByID(ctx, q, user, id)
	if err != nil {
		return Detail{}, err
	}
	r, err := rewards(ctx, q, user, id)
	if err != nil {
		return Detail{}, err
	}
	result := Detail{Attempt: item, Rewards: r}
	var reversal Reversal
	err = q.QueryRow(ctx, `SELECT id::text,attempt_id::text,reason,created_at FROM task_reversals WHERE user_id=$1 AND attempt_id=$2`, user, id).Scan(&reversal.ID, &reversal.AttemptID, &reversal.Reason, &reversal.CreatedAt)
	if err == nil {
		result.Reversal = &reversal
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return Detail{}, err
	}
	return result, nil
}
func readFailure(w http.ResponseWriter, err error) {
	if errors.Is(err, pgx.ErrNoRows) {
		err = apiutil.NotFound()
	}
	apiutil.WriteError(w, err)
}
func (s *Service) get(w http.ResponseWriter, r *http.Request) {
	if !validPath(w, r) {
		return
	}
	tx, err := s.DB.BeginTx(r.Context(), pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		readFailure(w, err)
		return
	}
	defer tx.Rollback(r.Context())
	value, err := Details(r.Context(), tx, auth.Current(r.Context()).ID, r.PathValue("id"))
	if err != nil {
		readFailure(w, err)
		return
	}
	apiutil.Write(w, 200, value)
}
func (s *Service) list(w http.ResponseWriter, r *http.Request) {
	if !validPath(w, r) {
		return
	}
	ctx := r.Context()
	user := auth.Current(ctx).ID
	id := r.PathValue("id")
	tx, err := s.DB.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		readFailure(w, err)
		return
	}
	defer tx.Rollback(ctx)
	current, err := task.ByID(ctx, tx, user, id)
	if err != nil {
		readFailure(w, err)
		return
	}
	var ids []string
	err = tx.QueryRow(ctx, `SELECT COALESCE(jsonb_agg(id::text ORDER BY attempt_no DESC),'[]'::jsonb) FROM task_attempts WHERE task_id=$1 AND user_id=$2`, id, user).Scan(&ids)
	if err != nil {
		readFailure(w, err)
		return
	}
	result := History{Items: []Detail{}, Summary: current.AttemptSummary}
	for _, id := range ids {
		detail, err := Details(ctx, tx, user, id)
		if err != nil {
			readFailure(w, err)
			return
		}
		result.Items = append(result.Items, detail)
	}
	apiutil.Write(w, 200, result)
}
