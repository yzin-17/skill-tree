package stats

import (
	"encoding/json"
	"os"
	"testing"
	"time"
)

func TestStatsBucketContract(t *testing.T) {
	data, err := os.ReadFile("../../contracts/stats.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Fixtures []struct {
			Timezone, Bucket string
			At, Start        time.Time
		} `json:"fixtures"`
	}
	if err = json.Unmarshal(data, &c); err != nil {
		t.Fatal(err)
	}
	for _, f := range c.Fixtures {
		zone, err := time.LoadLocation(f.Timezone)
		if err != nil {
			t.Fatal(err)
		}
		got := BucketStart(f.At, f.Bucket, zone)
		if !got.Equal(f.Start) {
			t.Fatal("时区分桶错误", got, f.Start)
		}
	}
	var totals Totals
	totals.Add(Fact{Kind: "attempt", Result: "failed"})
	totals.Add(Fact{Kind: "attempt", Result: "success"})
	if totals.Attempts.SuccessRate == nil || *totals.Attempts.SuccessRate != 0.5 {
		t.Fatal("有效尝试汇总错误")
	}
	zone, _ := time.LoadLocation("America/New_York")
	day := time.Date(2026, 11, 1, 0, 0, 0, 0, zone)
	if NextBucket(day, "day").Sub(day) != 25*time.Hour {
		t.Fatal("夏令时结束日应保留 25 小时边界")
	}
}
