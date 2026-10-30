package skill

import (
	"context"
	"fmt"
	"net/http"

	"github.com/jackc/pgx/v5"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
)

const treeColumns = `id::text,name,description,theme_key,sort_order,archived_at,version,created_at,updated_at`

func scanTree(row pgx.Row) (Tree, error) {
	var item Tree
	err := row.Scan(&item.ID, &item.Name, &item.Description, &item.ThemeKey, &item.SortOrder, &item.ArchivedAt, &item.Version, &item.CreatedAt, &item.UpdatedAt)
	return item, err
}
func TreeByID(ctx context.Context, q Queryer, user, id string) (Tree, error) {
	return scanTree(q.QueryRow(ctx, "SELECT "+treeColumns+" FROM skill_trees WHERE user_id=$1 AND id=$2", user, id))
}
func (s *Service) listTrees(w http.ResponseWriter, r *http.Request) {
	rows, err := s.DB.Query(r.Context(), "SELECT "+treeColumns+" FROM skill_trees WHERE user_id=$1 AND ($2 OR archived_at IS NULL) ORDER BY sort_order,created_at,id", auth.Current(r.Context()).ID, r.URL.Query().Get("include_archived") == "true")
	if err != nil {
		readError(w, err)
		return
	}
	defer rows.Close()
	items := []Tree{}
	for rows.Next() {
		item, err := scanTree(rows)
		if err != nil {
			readError(w, err)
			return
		}
		items = append(items, item)
	}
	if err = rows.Err(); err != nil {
		readError(w, err)
		return
	}
	apiutil.Write(w, 200, items)
}
func (s *Service) getTree(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	item, err := TreeByID(r.Context(), s.DB, auth.Current(r.Context()).ID, id)
	if err != nil {
		readError(w, err)
		return
	}
	apiutil.Write(w, 200, item)
}
func (s *Service) createTree(w http.ResponseWriter, r *http.Request) {
	var input TreeInput
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if err := input.Validate(true); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	domain.Mutate(w, r, s.DB, 201, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		digest := hash(input)
		exists, err := replay(ctx, tx, "skill_trees", input.ID, user.ID, digest)
		if err != nil {
			return nil, err
		}
		if exists {
			return TreeByID(ctx, tx, user.ID, input.ID)
		}
		_, err = tx.Exec(ctx, `INSERT INTO skill_trees(id,user_id,name,description,theme_key,sort_order,create_hash) VALUES($1,$2,$3,$4,$5,$6,$7)`, input.ID, user.ID, input.Name, input.Description, input.ThemeKey, input.SortOrder, digest)
		if err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "tree.created", "skill_tree", input.ID, "tree:"+input.ID+":created", "创建技能树「"+input.Name+"」")); err != nil {
			return nil, err
		}
		return TreeByID(ctx, tx, user.ID, input.ID)
	})
}
func (s *Service) editTree(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var input TreeInput
	if err := apiutil.Decode(w, r, &input); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	if input.ID != "" && input.ID != id {
		apiutil.WriteError(w, apiutil.Fail(400, "id_mismatch", "路径与记录标识不同。"))
		return
	}
	input.ID = id
	if err := input.Validate(false); err != nil {
		apiutil.WriteError(w, err)
		return
	}
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		existing, err := TreeByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		if existing.Version != input.Version {
			return nil, versionError()
		}
		_, err = tx.Exec(ctx, `UPDATE skill_trees SET name=$1,description=$2,theme_key=$3,sort_order=$4,archived_at=CASE WHEN $5 THEN COALESCE(archived_at,now()) ELSE NULL END,version=version+1,updated_at=now() WHERE id=$6 AND user_id=$7`, input.Name, input.Description, input.ThemeKey, input.SortOrder, input.Archived, id, user.ID)
		if err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "tree.updated", "skill_tree", id, fmt.Sprintf("tree:%s:v%d", id, input.Version+1), "更新技能树「"+input.Name+"」")); err != nil {
			return nil, err
		}
		return TreeByID(ctx, tx, user.ID, id)
	})
}
