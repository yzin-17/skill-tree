package focus

import (
	"skillatlas/internal/apiutil"
	"skillatlas/internal/growth"
	"time"
	"unicode/utf8"
)

type Input struct {
	ID               string    `json:"id"`
	SkillID          string    `json:"skill_id"`
	TaskID           *string   `json:"task_id"`
	Mode             string    `json:"mode"`
	TargetSeconds    *int64    `json:"target_seconds"`
	EffectiveSeconds int64     `json:"effective_seconds"`
	StartedAt        time.Time `json:"started_at"`
	EndedAt          time.Time `json:"ended_at"`
	Note             string    `json:"note"`
	Source           string    `json:"source"`
	PomodoroRounds   int       `json:"pomodoro_rounds"`
}
type Session struct {
	ID               string     `json:"id"`
	SkillID          string     `json:"skill_id"`
	TaskID           *string    `json:"task_id"`
	Mode             string     `json:"mode"`
	TargetSeconds    *int64     `json:"target_seconds"`
	EffectiveSeconds int64      `json:"effective_seconds"`
	StartedAt        time.Time  `json:"started_at"`
	EndedAt          time.Time  `json:"ended_at"`
	Note             string     `json:"note"`
	Source           string     `json:"source"`
	PomodoroRounds   int        `json:"pomodoro_rounds"`
	Version          int        `json:"version"`
	CreatedAt        time.Time  `json:"created_at"`
	InvalidatedAt    *time.Time `json:"invalidated_at"`
	ClockAdjusted    bool       `json:"clock_adjusted"`
}
type Settlement struct {
	Session         Session         `json:"session"`
	AwardedXP       int64           `json:"awarded_xp"`
	SettledProgress growth.Progress `json:"settled_progress"`
}
type Page struct {
	Items        []Session `json:"items"`
	NextCursor   string    `json:"next_cursor"`
	TotalSeconds int64     `json:"total_seconds"`
	Count        int64     `json:"count"`
}

func (v *Input) Validate() error {
	if !apiutil.ValidID(v.ID) || !apiutil.ValidID(v.SkillID) || (v.TaskID != nil && !apiutil.ValidID(*v.TaskID)) {
		return apiutil.Fail(400, "invalid_reference", "会话、技能或任务标识无效。")
	}
	if v.EffectiveSeconds < 0 || v.EffectiveSeconds > 2678400 || v.StartedAt.IsZero() || v.EndedAt.IsZero() || utf8.RuneCountInString(v.Note) > 4000 {
		return apiutil.Fail(400, "invalid_focus", "有效秒数、时间或备注无效。")
	}
	v.StartedAt = v.StartedAt.UTC()
	v.EndedAt = v.EndedAt.UTC()
	switch v.Mode {
	case "manual":
		if v.Source != "manual" || v.EffectiveSeconds < 1 || v.TargetSeconds != nil || v.EndedAt.Before(v.StartedAt) || float64(v.EffectiveSeconds) > v.EndedAt.Sub(v.StartedAt).Seconds()+1 {
			return apiutil.Fail(400, "invalid_manual", "补录区间必须容纳有效时长。")
		}
	case "count_up":
		if v.Source != "timer" || v.TargetSeconds != nil {
			return apiutil.Fail(400, "invalid_timer", "正计时参数无效。")
		}
	case "countdown", "pomodoro":
		if v.Source != "timer" || v.TargetSeconds == nil || *v.TargetSeconds < 1 || *v.TargetSeconds > 86400 {
			return apiutil.Fail(400, "invalid_target", "目标时间必须为 1–86400 秒。")
		}
		if v.Mode == "countdown" && v.EffectiveSeconds > *v.TargetSeconds {
			return apiutil.Fail(400, "invalid_duration", "倒计时有效时间超过目标。")
		}
		if v.Mode == "pomodoro" && (v.PomodoroRounds < 1 || v.PomodoroRounds > 24 || v.EffectiveSeconds > *v.TargetSeconds*int64(v.PomodoroRounds)) {
			return apiutil.Fail(400, "invalid_rounds", "番茄轮数或有效时间无效。")
		}
	default:
		return apiutil.Fail(400, "invalid_mode", "专注模式无效。")
	}
	if v.Mode != "pomodoro" && v.PomodoroRounds != 0 {
		return apiutil.Fail(400, "invalid_rounds", "当前模式不使用番茄轮数。")
	}
	return nil
}
