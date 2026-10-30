package export

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"time"
)

type Service struct{ DB *pgxpool.Pool }

func (s *Service) Register(mux *http.ServeMux, identity *auth.Service) {
	mux.HandleFunc("GET /v1/export", identity.Require(s.export))
}
func Read(ctx context.Context, tx pgx.Tx, user auth.User) (Document, error) {
	d := Document{Format: "skill-atlas-export", FormatVersion: 1, ExportedAt: time.Now().UTC(), Account: user, Datasets: map[string][]json.RawMessage{}, Counts: map[string]int{}}
	for _, set := range datasets {
		var rows []json.RawMessage
		query := "SELECT COALESCE(jsonb_agg(to_jsonb(record)),'[]'::jsonb) FROM (SELECT " + set.Columns + " FROM " + set.Name + " WHERE user_id=$1 ORDER BY " + set.Order + ") record"
		if err := tx.QueryRow(ctx, query, user.ID).Scan(&rows); err != nil {
			return Document{}, err
		}
		d.Datasets[set.Name] = rows
		d.Counts[set.Name] = len(rows)
	}
	if err := d.Validate(); err != nil {
		return Document{}, err
	}
	return d, nil
}
func (s *Service) export(w http.ResponseWriter, r *http.Request) {
	tx, err := s.DB.BeginTx(r.Context(), pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	defer tx.Rollback(r.Context())
	d, err := Read(r.Context(), tx, auth.Current(r.Context()))
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, 200, d)
}
