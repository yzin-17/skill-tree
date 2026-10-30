package export

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"skillatlas/internal/apiutil"
	"skillatlas/internal/auth"
	"time"
)

type Document struct {
	Format        string                       `json:"format"`
	FormatVersion int                          `json:"format_version"`
	ExportedAt    time.Time                    `json:"exported_at"`
	Account       auth.User                    `json:"account"`
	Datasets      map[string][]json.RawMessage `json:"datasets"`
	Counts        map[string]int               `json:"counts"`
}
type dataset struct{ Name, Columns, Order string }

var datasets = []dataset{
	{"skill_trees", "id,name,description,theme_key,sort_order,archived_at,version,created_at,updated_at", "id"},
	{"skills", "id,tree_id,parent_skill_id,name,description,icon_key,sort_order,archived_at,version,created_at,updated_at", "id"},
	{"skill_links", "id,from_skill_id,to_skill_id,link_type,required_level,version,created_at,deleted_at", "id"},
	{"tasks", "id,title,description,success_criteria,status,due_at,pinned,current_attempt_no,version,created_at,updated_at", "id"},
	{"task_skills", "task_id,skill_id,reward_levels,created_at", "task_id,skill_id"},
	{"focus_sessions", "id,skill_id,task_id,mode,target_seconds,effective_seconds,started_at,ended_at,note,source,pomodoro_rounds,version,created_at,invalidated_at,clock_adjusted,awarded_xp,settled_progress", "id"},
	{"task_attempts", "id,task_id,attempt_no,result,reason,concluded_at,reversed_at", "id"},
	{"task_attempt_skills", "attempt_id,skill_id,reward_levels", "attempt_id,skill_id"},
	{"task_rewards", "id,attempt_id,skill_id,reward_levels_snapshot,xp_amount,growth_event_id,created_at", "id"},
	{"task_retry_requests", "id,task_id,previous_attempt_no,next_attempt_no,created_at", "id"},
	{"task_reversals", "id,attempt_id,reason,created_at", "id"},
	{"growth_events", "id,skill_id,event_type,source_id,delta_xp,note,created_at,reverses_event_id", "id"},
	{"activity_events", "id,type,producer,entity_type,entity_id,source_key,summary,skill_ids,metadata,occurred_at,created_at", "id"},
	{"career_nodes", "id,name,description,badge_key,parent_career_id,sort_order,conditions_json,version,created_at,updated_at", "id"},
	{"career_transitions", "id,from_career_id,to_career_id,conditions_snapshot,evidence_snapshot,confirmed_at", "id"},
	{"titles", "id,name,description,icon_key,conditions_json,version,created_at,updated_at", "id"},
	{"user_titles", "title_id,unlocked_at,equipped_at,conditions_snapshot,evidence_snapshot", "title_id"},
	{"achievement_profiles", "current_career_id,equipped_title_id", "user_id"},
	{"achievement_references", "entity_type,entity_id,reference_type,reference_id,skill_id,task_id", "entity_type,entity_id,reference_type,reference_id"},
	{"achievement_commands", "id,kind,target_id,created_at", "id"},
}

func (d Document) Validate() error {
	if d.Format != "skill-atlas-export" || d.FormatVersion != 1 || !apiutil.ValidID(d.Account.ID) || d.ExportedAt.IsZero() || len(d.Datasets) != len(datasets) || len(d.Counts) != len(datasets) {
		return fmt.Errorf("导出格式、版本或账号无效")
	}
	objects := map[string][]map[string]any{}
	ids := map[string]map[string]bool{}
	for _, set := range datasets {
		rows, ok := d.Datasets[set.Name]
		count, countOK := d.Counts[set.Name]
		if !ok || !countOK || rows == nil || len(rows) != count {
			return fmt.Errorf("数据集 %s 数量不一致", set.Name)
		}
		ids[set.Name] = map[string]bool{}
		for _, raw := range rows {
			var row map[string]any
			if err := json.Unmarshal(raw, &row); err != nil {
				return err
			}
			if err := privateKeys(row); err != nil {
				return err
			}
			objects[set.Name] = append(objects[set.Name], row)
			if id, ok := row["id"].(string); ok {
				if !apiutil.ValidID(id) {
					return fmt.Errorf("数据集 %s 标识无效", set.Name)
				}
				if ids[set.Name][id] {
					return fmt.Errorf("数据集 %s 存在重复标识", set.Name)
				}
				ids[set.Name][id] = true
			} else if len(set.Columns) >= 3 && set.Columns[:3] == "id," {
				return fmt.Errorf("数据集 %s 缺少标识", set.Name)
			}
		}
	}
	refs := map[string]map[string]string{
		"skills": {"tree_id": "skill_trees", "parent_skill_id": "skills"}, "skill_links": {"from_skill_id": "skills", "to_skill_id": "skills"}, "task_skills": {"task_id": "tasks", "skill_id": "skills"},
		"focus_sessions": {"skill_id": "skills", "task_id": "tasks"}, "task_attempts": {"task_id": "tasks"}, "task_attempt_skills": {"attempt_id": "task_attempts", "skill_id": "skills"},
		"task_rewards": {"attempt_id": "task_attempts", "skill_id": "skills", "growth_event_id": "growth_events"}, "task_retry_requests": {"task_id": "tasks"}, "task_reversals": {"attempt_id": "task_attempts"},
		"growth_events": {"skill_id": "skills", "reverses_event_id": "growth_events"}, "career_nodes": {"parent_career_id": "career_nodes"}, "career_transitions": {"from_career_id": "career_nodes", "to_career_id": "career_nodes"},
		"user_titles": {"title_id": "titles"}, "achievement_profiles": {"current_career_id": "career_nodes", "equipped_title_id": "titles"}, "achievement_references": {"skill_id": "skills", "task_id": "tasks"},
	}
	for name, fields := range refs {
		for _, row := range objects[name] {
			for field, target := range fields {
				optional := field == "parent_skill_id" || field == "parent_career_id" || field == "from_career_id" || field == "reverses_event_id" || name == "achievement_profiles" || name == "achievement_references" || (name == "focus_sessions" && field == "task_id")
				if row[field] == nil && !optional {
					return fmt.Errorf("%s.%s 缺少必需引用", name, field)
				}
				if raw := row[field]; raw != nil {
					id, ok := raw.(string)
					if !ok || !ids[target][id] {
						return fmt.Errorf("%s.%s 引用缺失", name, field)
					}
				}
			}
		}
	}
	for _, row := range objects["growth_events"] {
		target := "task_attempts"
		if row["event_type"] == "focus_accrual" {
			target = "focus_sessions"
		}
		id, _ := row["source_id"].(string)
		if !ids[target][id] {
			return fmt.Errorf("成长来源缺失")
		}
	}
	return nil
}

func Parse(data []byte) (Document, error) {
	var d Document
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&d); err != nil {
		return d, err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return d, fmt.Errorf("导出文件包含额外内容")
	}
	return d, d.Validate()
}
func privateKeys(value any) error {
	switch value := value.(type) {
	case map[string]any:
		for key, item := range value {
			switch key {
			case "password_hash", "token", "token_hash", "request_hash", "create_hash", "result_json":
				return fmt.Errorf("导出包含禁止字段 %s", key)
			}
			if err := privateKeys(item); err != nil {
				return err
			}
		}
	case []any:
		for _, item := range value {
			if err := privateKeys(item); err != nil {
				return err
			}
		}
	}
	return nil
}
