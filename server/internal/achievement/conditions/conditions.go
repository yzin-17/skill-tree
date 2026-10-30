package conditions

import (
	"encoding/json"
	"skillatlas/internal/apiutil"
)

type Condition struct {
	Type    string  `json:"type"`
	SkillID *string `json:"skill_id,omitempty"`
	TaskID  *string `json:"task_id,omitempty"`
	GTE     *int64  `json:"gte,omitempty"`
}
type Set struct {
	All []Condition `json:"all"`
}
type Fact struct {
	Current    int64
	SourceType string
	SourceIDs  []string
	Truncated  bool
}
type Evidence struct {
	Condition        Condition `json:"condition"`
	Current          int64     `json:"current"`
	Required         int64     `json:"required"`
	Met              bool      `json:"met"`
	Unit             string    `json:"unit"`
	SourceType       string    `json:"source_type"`
	SourceIDs        []string  `json:"source_ids"`
	SourcesTruncated bool      `json:"sources_truncated"`
}
type Evaluation struct {
	Eligible bool       `json:"eligible"`
	Evidence []Evidence `json:"evidence"`
}

func (s Set) Validate() error {
	if len(s.All) < 1 || len(s.All) > 32 {
		return apiutil.Fail(400, "invalid_conditions", "请配置 1–32 项条件。")
	}
	seen := map[string]bool{}
	for _, v := range s.All {
		if v.SkillID != nil && !apiutil.ValidID(*v.SkillID) || v.TaskID != nil && !apiutil.ValidID(*v.TaskID) {
			return apiutil.Fail(400, "invalid_condition_reference", "条件引用标识无效。")
		}
		switch v.Type {
		case "skill_level", "focus_minutes":
			if v.SkillID == nil || v.TaskID != nil || v.GTE == nil {
				return apiutil.Fail(400, "invalid_condition", "等级或时长条件必须指定技能和阈值。")
			}
		case "task_success_count":
			if v.TaskID != nil || v.GTE == nil {
				return apiutil.Fail(400, "invalid_condition", "成功次数条件须设置阈值。")
			}
		case "specific_task_success":
			if v.SkillID != nil || v.TaskID == nil || v.GTE != nil {
				return apiutil.Fail(400, "invalid_condition", "指定任务成功条件只能选择任务。")
			}
		default:
			return apiutil.Fail(400, "invalid_condition_type", "条件类型无效。")
		}
		if v.GTE != nil && (*v.GTE < 1 || *v.GTE > 1000000) {
			return apiutil.Fail(400, "invalid_threshold", "条件阈值必须为 1–1000000。")
		}
		key, _ := json.Marshal(struct {
			Type            string
			SkillID, TaskID *string
		}{v.Type, v.SkillID, v.TaskID})
		if seen[string(key)] {
			return apiutil.Fail(400, "duplicate_condition", "相同对象的同类条件只能配置一次。")
		}
		seen[string(key)] = true
	}
	return nil
}
func Evaluate(s Set, facts []Fact) (Evaluation, error) {
	if err := s.Validate(); err != nil {
		return Evaluation{}, err
	}
	if len(facts) != len(s.All) {
		return Evaluation{}, apiutil.Fail(500, "missing_facts", "条件事实不完整。")
	}
	result := Evaluation{Eligible: true, Evidence: []Evidence{}}
	for i, c := range s.All {
		required := int64(1)
		if c.GTE != nil {
			required = *c.GTE
		}
		unit := "次"
		if c.Type == "skill_level" {
			unit = "级"
		} else if c.Type == "focus_minutes" {
			unit = "分钟"
		}
		f := facts[i]
		ids := f.SourceIDs
		if ids == nil {
			ids = []string{}
		}
		met := f.Current >= required
		result.Evidence = append(result.Evidence, Evidence{Condition: c, Current: f.Current, Required: required, Met: met, Unit: unit, SourceType: f.SourceType, SourceIDs: ids, SourcesTruncated: f.Truncated})
		result.Eligible = result.Eligible && met
	}
	return result, nil
}
