package edgeerrors

import (
	"encoding/json"
	"net/http/httptest"
	"testing"
)

func TestWriteJSON(t *testing.T) {
	recorder := httptest.NewRecorder()

	WriteJSON(recorder, 418, "invalid_request", "bad request", "req-123")

	if recorder.Code != 418 {
		t.Fatalf("status = %d, want 418", recorder.Code)
	}

	var payload map[string]map[string]string
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}

	if payload["error"]["code"] != "invalid_request" {
		t.Fatalf("code = %q, want invalid_request", payload["error"]["code"])
	}
	if payload["error"]["request_id"] != "req-123" {
		t.Fatalf("request_id = %q, want req-123", payload["error"]["request_id"])
	}
}
