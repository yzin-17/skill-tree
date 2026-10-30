package httpapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"skillatlas/internal/httpapi"
	"skillatlas/internal/storage"
	"skillatlas/internal/testdb"
)

func TestHealthWithRealDatabase(t *testing.T) {
	pool := testdb.Open(t)
	if err := storage.Migrate(context.Background(), pool); err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(httpapi.New(pool))
	defer server.Close()
	response, err := http.Get(server.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	var data struct {
		Data struct {
			Status   string `json:"status"`
			Database string `json:"database"`
		} `json:"data"`
	}
	if err := json.NewDecoder(response.Body).Decode(&data); err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != 200 || data.Data.Status != "ok" || data.Data.Database != "ready" {
		t.Fatalf("unexpected health: status %d, %+v", response.StatusCode, data)
	}
	pool.Close()
	response, err = http.Get(server.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 503 {
		t.Fatalf("unavailable database returned %d", response.StatusCode)
	}
}
