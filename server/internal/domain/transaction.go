package domain

import (
	"context"
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
)

// 按账号串行化短事务，保证层级、XP、尝试和事件的一致性。
func Mutate(w http.ResponseWriter, r *http.Request, pool *pgxpool.Pool, status int, action func(context.Context, pgx.Tx, auth.User) (any, error)) {
	user := auth.Current(r.Context())
	ctx := r.Context()
	tx, err := pool.Begin(ctx)
	if err != nil {
		apiutil.WriteError(w, err)
		return
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "account:"+user.ID); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	output, err := action(ctx, tx, user)
	if err == nil {
		err = tx.Commit(ctx)
	}
	if err != nil {
		var pg *pgconn.PgError
		if errors.Is(err, pgx.ErrNoRows) {
			err = apiutil.NotFound()
		}
		if errors.As(err, &pg) {
			switch pg.Code {
			case "23505":
				err = apiutil.Fail(409, "duplicate", "该记录已存在，请刷新后重试。")
			case "23503":
				err = apiutil.Fail(409, "referenced", "记录仍被历史或其他对象引用，请使用归档。")
			case "22P02", "23514":
				err = apiutil.Fail(400, "invalid_input", "字段值不符合约束。")
			}
		}
		apiutil.WriteError(w, err)
		return
	}
	apiutil.Write(w, status, output)
}
