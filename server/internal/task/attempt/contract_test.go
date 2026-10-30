package attempt

import (
	"encoding/json"
	"os"
	"skillatlas/internal/task"
	"testing"
)

func TestAttemptContract(t *testing.T) {
	data, err := os.ReadFile("../../../contracts/attempt.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var contract struct {
		Fixtures struct {
			Conclude Conclusion `json:"conclude"`
			Counts   []struct {
				Successes, Failures int64
				Rate                *float64
			} `json:"counts"`
		} `json:"fixtures"`
	}
	if err = json.Unmarshal(data, &contract); err != nil {
		t.Fatal(err)
	}
	if err = contract.Fixtures.Conclude.Validate(); err != nil {
		t.Fatal(err)
	}
	for _, f := range contract.Fixtures.Counts {
		s := task.SummarizeAttempts(f.Successes, f.Failures, 0)
		if (s.SuccessRate == nil) != (f.Rate == nil) || (f.Rate != nil && *s.SuccessRate != *f.Rate) {
			t.Fatal("有效尝试口径错误")
		}
	}
	bad := contract.Fixtures.Conclude
	bad.Result = "canceled"
	if bad.Validate() == nil {
		t.Fatal("取消不应形成尝试")
	}
}
