package task

import (
	"skillatlas/internal/apiutil"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

type Binding struct {
	SkillID      string `json:"skill_id"`
	RewardLevels int64  `json:"reward_levels"`
}
type Input struct {
	ID              string     `json:"id"`
	Title           string     `json:"title"`
	Description     string     `json:"description"`
	SuccessCriteria string     `json:"success_criteria"`
	Status          string     `json:"status"`
	DueAt           *time.Time `json:"due_at"`
	Pinned          bool       `json:"pinned"`
	Skills          []Binding  `json:"skills"`
	Version         int        `json:"version"`
}
type Task struct {
	AttemptSummary    AttemptSummary `json:"attempt_summary"`
	TotalFocusSeconds int64          `json:"total_focus_seconds"`
	FocusCount        int64          `json:"focus_count"`
	ID                string         `json:"id"`
	Title             string         `json:"title"`
	Description       string         `json:"description"`
	SuccessCriteria   string         `json:"success_criteria"`
	Status            string         `json:"status"`
	DueAt             *time.Time     `json:"due_at"`
	Pinned            bool           `json:"pinned"`
	Skills            []Binding      `json:"skills"`
	Version           int            `json:"version"`
	CurrentAttemptNo  int            `json:"current_attempt_no"`
	CreatedAt         time.Time      `json:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at"`
}

type AttemptSummary struct {
	Total       int64    `json:"total"`
	Successes   int64    `json:"successes"`
	Failures    int64    `json:"failures"`
	Retries     int64    `json:"retries"`
	SuccessRate *float64 `json:"success_rate"`
}

func SummarizeAttempts(successes, failures, retries int64) AttemptSummary {
	result := AttemptSummary{Total: successes + failures, Successes: successes, Failures: failures, Retries: retries}
	if result.Total > 0 {
		rate := float64(successes) / float64(result.Total)
		result.SuccessRate = &rate
	}
	return result
}

func ValidStatus(value string) bool {
	switch value {
	case "todo", "in_progress", "success", "failed", "canceled":
		return true
	}
	return false
}
func (v *Input) Validate(create bool) error {
	v.Title = strings.TrimSpace(v.Title)
	if v.Status == "" {
		v.Status = "todo"
	}
	if v.Skills == nil {
		v.Skills = []Binding{}
	}
	if !apiutil.ValidID(v.ID) || utf8.RuneCountInString(v.Title) < 1 || utf8.RuneCountInString(v.Title) > 140 || utf8.RuneCountInString(v.Description) > 10000 || utf8.RuneCountInString(v.SuccessCriteria) > 4000 || len(v.Skills) > 64 || !ValidStatus(v.Status) {
		return apiutil.Fail(400, "invalid_task", "任务字段无效。")
	}
	if create && (v.Version != 0 || (v.Status != "todo" && v.Status != "in_progress")) || !create && v.Version < 1 {
		return apiutil.Fail(400, "invalid_state", "创建或编辑状态/版本无效。")
	}
	seen := map[string]bool{}
	for _, binding := range v.Skills {
		if !apiutil.ValidID(binding.SkillID) || seen[binding.SkillID] || binding.RewardLevels < 0 || binding.RewardLevels > 1000000 {
			return apiutil.Fail(400, "invalid_rewards", "关联技能不得重复，奖励须为 0–1000000 的整数。")
		}
		seen[binding.SkillID] = true
	}
	sort.Slice(v.Skills, func(i, j int) bool { return v.Skills[i].SkillID < v.Skills[j].SkillID })
	return nil
}
func ValidateEdit(old, new string) error {
	if old == new {
		return nil
	}
	if (old == "todo" || old == "in_progress") && (new == "todo" || new == "in_progress" || new == "canceled") {
		return nil
	}
	if old == "failed" && new == "canceled" {
		return nil
	}
	return apiutil.Fail(409, "invalid_transition", "请使用结算、重试或撤销操作修改当前状态。")
}
