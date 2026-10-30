package export

import (
	"encoding/json"
	"os"
	"testing"
)

func TestExportContractReader(t *testing.T) {
	data, err := os.ReadFile("../../contracts/export.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var contract struct {
		Datasets []string `json:"datasets"`
		Fixture  Document `json:"fixture"`
	}
	if err = json.Unmarshal(data, &contract); err != nil {
		t.Fatal(err)
	}
	for _, name := range contract.Datasets {
		contract.Fixture.Datasets[name] = []json.RawMessage{}
		contract.Fixture.Counts[name] = 0
	}
	if err = contract.Fixture.Validate(); err != nil {
		t.Fatal(err)
	}
	contract.Fixture.Datasets["skills"] = []json.RawMessage{json.RawMessage(`{"id":"missing-tree-skill","tree_id":"missing"}`)}
	contract.Fixture.Counts["skills"] = 1
	if contract.Fixture.Validate() == nil {
		t.Fatal("缺失引用未拒绝")
	}
	contract.Fixture.Datasets["skills"] = []json.RawMessage{json.RawMessage(`{"id":"invalid","token":"forbidden"}`)}
	if contract.Fixture.Validate() == nil {
		t.Fatal("禁止字段未拒绝")
	}
}
