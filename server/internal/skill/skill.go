package skill

import (
	"context"
	"fmt"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5"
	"skillatlas/internal/activity"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"skillatlas/internal/domain"
)

const skillColumns = `s.id::text,s.tree_id::text,s.parent_skill_id::text,s.name,s.description,s.icon_key,s.sort_order,s.archived_at,s.version,s.created_at,s.updated_at`

func scanSkill(row pgx.Row) (Skill, error) {
	var item Skill
	err := row.Scan(&item.ID, &item.TreeID, &item.ParentSkillID, &item.Name, &item.Description, &item.IconKey, &item.SortOrder, &item.ArchivedAt, &item.Version, &item.CreatedAt, &item.UpdatedAt)
	return item, err
}
func ByID(ctx context.Context, q Queryer, user, id string) (Skill, error) {
	return scanSkill(q.QueryRow(ctx, "SELECT "+skillColumns+" FROM skills s WHERE s.user_id=$1 AND s.id=$2", user, id))
}
func Available(ctx context.Context, q Queryer, user, id string) (Skill, error) {
	item, err := ByID(ctx, q, user, id)
	if err != nil {
		return item, err
	}
	tree, err := TreeByID(ctx, q, user, item.TreeID)
	if err != nil {
		return item, err
	}
	if item.ArchivedAt != nil || tree.ArchivedAt != nil {
		return item, archiveError()
	}
	return item, nil
}
func (s *Service) listSkills(w http.ResponseWriter, r *http.Request) {
	tree := r.URL.Query().Get("tree_id")
	if tree != "" && !apiutil.ValidID(tree) {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_id", "技能树标识无效。"))
		return
	}
	rows, err := s.DB.Query(r.Context(), "SELECT "+skillColumns+" FROM skills s JOIN skill_trees t ON t.id=s.tree_id WHERE s.user_id=$1 AND ($2='' OR s.tree_id::text=$2) AND ($3 OR (s.archived_at IS NULL AND t.archived_at IS NULL)) ORDER BY s.sort_order,s.created_at,s.id", auth.Current(r.Context()).ID, tree, r.URL.Query().Get("include_archived") == "true")
	if err != nil {
		readError(w, err)
		return
	}
	defer rows.Close()
	items := []Skill{}
	for rows.Next() {
		item, err := scanSkill(rows)
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
func (s *Service) getSkill(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	item, err := ByID(r.Context(), s.DB, auth.Current(r.Context()).ID, id)
	if err != nil {
		readError(w, err)
		return
	}
	apiutil.Write(w, 200, item)
}
func validateParent(ctx context.Context, tx pgx.Tx, user string, input SkillInput, oldParent *string) error {
	if input.ParentSkillID == nil {
		return nil
	}
	parent, err := ByID(ctx, tx, user, *input.ParentSkillID)
	if err != nil {
		return err
	}
	if parent.TreeID != input.TreeID {
		return apiutil.Fail(400, "cross_tree_parent", "父技能必须位于同一技能树。")
	}
	if parent.ArchivedAt != nil && (oldParent == nil || *oldParent != parent.ID) {
		return archiveError()
	}
	var cycle bool
	err = tx.QueryRow(ctx, `WITH RECURSIVE ancestors AS (SELECT id,parent_skill_id FROM skills WHERE id=$1 AND user_id=$2 UNION SELECT s.id,s.parent_skill_id FROM skills s JOIN ancestors a ON s.id=a.parent_skill_id WHERE s.user_id=$2) SELECT EXISTS(SELECT 1 FROM ancestors WHERE id=$3)`, parent.ID, user, input.ID).Scan(&cycle)
	if err != nil {
		return err
	}
	if cycle {
		return apiutil.Fail(400, "parent_cycle", "父子关系不能形成循环。")
	}
	return nil
}
func (s *Service) createSkill(w http.ResponseWriter, r *http.Request) {
	var input SkillInput
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
		exists, err := replay(ctx, tx, "skills", input.ID, user.ID, digest)
		if err != nil {
			return nil, err
		}
		if exists {
			return ByID(ctx, tx, user.ID, input.ID)
		}
		tree, err := TreeByID(ctx, tx, user.ID, input.TreeID)
		if err != nil {
			return nil, err
		}
		if tree.ArchivedAt != nil {
			return nil, archiveError()
		}
		if err = validateParent(ctx, tx, user.ID, input, nil); err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, `INSERT INTO skills(id,user_id,tree_id,parent_skill_id,name,description,icon_key,sort_order,create_hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, input.ID, user.ID, input.TreeID, input.ParentSkillID, input.Name, input.Description, input.IconKey, input.SortOrder, digest)
		if err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "skill.created", "skill", input.ID, "skill:"+input.ID+":created", "创建技能「"+input.Name+"」", input.ID)); err != nil {
			return nil, err
		}
		return ByID(ctx, tx, user.ID, input.ID)
	})
}
func (s *Service) editSkill(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var input SkillInput
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
		existing, err := ByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		if existing.Version != input.Version {
			return nil, versionError()
		}
		if existing.TreeID != input.TreeID {
			return nil, apiutil.Fail(400, "tree_immutable", "技能创建后不能更换所属树。")
		}
		if err = validateParent(ctx, tx, user.ID, input, existing.ParentSkillID); err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, `UPDATE skills SET parent_skill_id=$1,name=$2,description=$3,icon_key=$4,sort_order=$5,archived_at=CASE WHEN $6 THEN COALESCE(archived_at,now()) ELSE NULL END,version=version+1,updated_at=now() WHERE id=$7 AND user_id=$8`, input.ParentSkillID, input.Name, input.Description, input.IconKey, input.SortOrder, input.Archived, id, user.ID)
		if err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "skill.updated", "skill", id, fmt.Sprintf("skill:%s:v%d", id, input.Version+1), "更新技能「"+input.Name+"」", id)); err != nil {
			return nil, err
		}
		return ByID(ctx, tx, user.ID, id)
	})
}
func (s *Service) deleteSkill(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	version, err := strconv.Atoi(r.URL.Query().Get("version"))
	if err != nil || version < 1 {
		apiutil.WriteError(w, apiutil.Fail(400, "invalid_version", "删除需要当前版本。"))
		return
	}
	domain.Mutate(w, r, s.DB, 200, func(ctx context.Context, tx pgx.Tx, user auth.User) (any, error) {
		existing, err := ByID(ctx, tx, user.ID, id)
		if err != nil {
			return nil, err
		}
		if existing.Version != version {
			return nil, versionError()
		}
		if _, err = tx.Exec(ctx, `DELETE FROM skills WHERE id=$1 AND user_id=$2`, id, user.ID); err != nil {
			return nil, err
		}
		if err = activity.Append(ctx, tx, activity.ServerEvent(user.ID, "skill.deleted", "skill", id, "skill:"+id+":deleted", "删除技能「"+existing.Name+"」", id)); err != nil {
			return nil, err
		}
		return map[string]bool{"deleted": true}, nil
	})
}
