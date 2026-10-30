package growth

type MissingPrerequisite struct {
	SkillID       string `json:"skill_id"`
	Name          string `json:"name"`
	RequiredLevel int64  `json:"required_level"`
	CurrentLevel  int64  `json:"current_level"`
}
type Progress struct {
	SkillID              string                `json:"skill_id"`
	TotalFocusSeconds    int64                 `json:"total_focus_seconds"`
	TimeXP               int64                 `json:"time_xp"`
	TaskBonusXP          int64                 `json:"task_bonus_xp"`
	TotalXP              int64                 `json:"total_xp"`
	Level                int64                 `json:"level"`
	XPCurrent            int64                 `json:"xp_current"`
	XPRequired           int64                 `json:"xp_required"`
	Unlocked             bool                  `json:"unlocked"`
	MissingPrerequisites []MissingPrerequisite `json:"missing_prerequisites"`
}

func FocusXP(before, added int64) int64 { return (before+added)/60 - before/60 }
func Calculate(skill string, seconds, timeXP, bonusXP int64) Progress {
	total := timeXP + bonusXP
	return Progress{SkillID: skill, TotalFocusSeconds: seconds, TimeXP: timeXP, TaskBonusXP: bonusXP, TotalXP: total, Level: 1 + total/60, XPCurrent: total % 60, XPRequired: 60, Unlocked: true, MissingPrerequisites: []MissingPrerequisite{}}
}
