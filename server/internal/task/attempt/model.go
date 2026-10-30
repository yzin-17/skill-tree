package attempt

import (
	"skillatlas/internal/apiutil"
	"skillatlas/internal/growth"
	"skillatlas/internal/task"
	"time"
	"unicode/utf8"
)

type Conclusion struct {
	ID        string `json:"id"`
	AttemptNo int    `json:"attempt_no"`
	Version   int    `json:"version"`
	Result    string `json:"result"`
	Reason    string `json:"reason"`
}

func (v Conclusion) Validate() error {
	if !apiutil.ValidID(v.ID) || v.AttemptNo < 1 || v.Version < 1 || (v.Result != "success" && v.Result != "failed") || utf8.RuneCountInString(v.Reason) > 4000 {
		return apiutil.Fail(400, "invalid_attempt", "尝试编号、状态或说明无效。")
	}
	return nil
}

type RetryInput struct {
	ID        string `json:"id"`
	AttemptNo int    `json:"attempt_no"`
	Version   int    `json:"version"`
}
type ReverseInput struct {
	ID     string `json:"id"`
	Reason string `json:"reason"`
}
type Attempt struct {
	ID            string         `json:"id"`
	TaskID        string         `json:"task_id"`
	AttemptNo     int            `json:"attempt_no"`
	Result        string         `json:"result"`
	Reason        string         `json:"reason"`
	SkillSnapshot []task.Binding `json:"skill_snapshot"`
	ConcludedAt   time.Time      `json:"concluded_at"`
	ReversedAt    *time.Time     `json:"reversed_at"`
}
type Reward struct {
	ID                   string `json:"id"`
	AttemptID            string `json:"attempt_id"`
	SkillID              string `json:"skill_id"`
	RewardLevelsSnapshot int64  `json:"reward_levels_snapshot"`
	XPAmount             int64  `json:"xp_amount"`
	GrowthEventID        string `json:"growth_event_id"`
}
type Reversal struct {
	ID        string    `json:"id"`
	AttemptID string    `json:"attempt_id"`
	Reason    string    `json:"reason"`
	CreatedAt time.Time `json:"created_at"`
}
type Detail struct {
	Attempt  Attempt   `json:"attempt"`
	Rewards  []Reward  `json:"rewards"`
	Reversal *Reversal `json:"reversal"`
}
type Settlement struct {
	Detail
	Task            task.Task         `json:"task"`
	SettledProgress []growth.Progress `json:"settled_progress"`
}
type History struct {
	Items   []Detail            `json:"items"`
	Summary task.AttemptSummary `json:"summary"`
}
