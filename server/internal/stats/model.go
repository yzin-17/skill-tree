package stats

import (
	"encoding/json"
	"skillatlas/internal/task"
	"time"
)

type Totals struct {
	FocusSeconds  int64               `json:"focus_seconds"`
	TimerSeconds  int64               `json:"timer_seconds"`
	ManualSeconds int64               `json:"manual_seconds"`
	FocusCount    int64               `json:"focus_count"`
	TimeXP        int64               `json:"time_xp"`
	TaskBonusXP   int64               `json:"task_bonus_xp"`
	TotalXP       int64               `json:"total_xp"`
	Attempts      task.AttemptSummary `json:"attempts"`
}
type Sources struct {
	FocusIDs   []string `json:"focus_ids"`
	GrowthIDs  []string `json:"growth_ids"`
	AttemptIDs []string `json:"attempt_ids"`
	RetryIDs   []string `json:"retry_ids"`
}

func EmptySources() Sources {
	return Sources{FocusIDs: []string{}, GrowthIDs: []string{}, AttemptIDs: []string{}, RetryIDs: []string{}}
}

type Bucket struct {
	Start   time.Time `json:"start"`
	Label   string    `json:"label"`
	Totals  Totals    `json:"totals"`
	Sources Sources   `json:"sources"`
}
type SkillSummary struct {
	SkillID string `json:"skill_id"`
	TreeID  string `json:"tree_id"`
	Name    string `json:"name"`
	Totals  Totals `json:"totals"`
}
type Summary struct {
	Timezone      string          `json:"timezone"`
	From          time.Time       `json:"from"`
	To            time.Time       `json:"to"`
	Bucket        string          `json:"bucket"`
	AllTime       Totals          `json:"all_time"`
	Totals        Totals          `json:"totals"`
	Series        []Bucket        `json:"series"`
	Skills        []SkillSummary  `json:"skills"`
	Sources       Sources         `json:"sources"`
	CareerHistory json.RawMessage `json:"career_history"`
	TitleHistory  json.RawMessage `json:"title_history"`
	HistoryScope  string          `json:"history_scope"`
}
type Fact struct {
	ID        string    `json:"id"`
	Kind      string    `json:"kind"`
	At        time.Time `json:"at"`
	SkillIDs  []string  `json:"skill_ids"`
	Seconds   int64     `json:"seconds"`
	Source    string    `json:"source"`
	DeltaXP   int64     `json:"delta_xp"`
	EventType string    `json:"event_type"`
	Result    string    `json:"result"`
}

func (t *Totals) Add(f Fact) {
	switch f.Kind {
	case "focus":
		t.FocusCount++
		t.FocusSeconds += f.Seconds
		if f.Source == "timer" {
			t.TimerSeconds += f.Seconds
		} else {
			t.ManualSeconds += f.Seconds
		}
	case "growth":
		if f.EventType == "focus_accrual" {
			t.TimeXP += f.DeltaXP
		} else {
			t.TaskBonusXP += f.DeltaXP
		}
		t.TotalXP = t.TimeXP + t.TaskBonusXP
	case "attempt":
		if f.Result == "success" {
			t.Attempts.Successes++
		} else {
			t.Attempts.Failures++
		}
	case "retry":
		t.Attempts.Retries++
	}
	t.Attempts = task.SummarizeAttempts(t.Attempts.Successes, t.Attempts.Failures, t.Attempts.Retries)
}
func (s *Sources) Add(f Fact) {
	switch f.Kind {
	case "focus":
		s.FocusIDs = append(s.FocusIDs, f.ID)
	case "growth":
		s.GrowthIDs = append(s.GrowthIDs, f.ID)
	case "attempt":
		s.AttemptIDs = append(s.AttemptIDs, f.ID)
	case "retry":
		s.RetryIDs = append(s.RetryIDs, f.ID)
	}
}
func BucketStart(at time.Time, kind string, zone *time.Location) time.Time {
	local := at.In(zone)
	y, m, d := local.Date()
	if kind == "month" {
		d = 1
	} else if kind == "week" {
		d -= (int(local.Weekday()) + 6) % 7
	}
	return time.Date(y, m, d, 0, 0, 0, 0, zone)
}
func NextBucket(start time.Time, kind string) time.Time {
	switch kind {
	case "month":
		return start.AddDate(0, 1, 0)
	case "week":
		return start.AddDate(0, 0, 7)
	default:
		return start.AddDate(0, 0, 1)
	}
}
