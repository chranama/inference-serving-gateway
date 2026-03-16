package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRequestIdentityPreservesInboundHeaders(t *testing.T) {
	var gotRequestID string
	var gotTraceID string

	handler := RequestIdentity(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotRequestID = GetRequestID(r.Context())
		gotTraceID = GetTraceID(r.Context())
	}))

	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	request.Header.Set("X-Request-ID", "req-existing")
	request.Header.Set("X-Trace-ID", "trace-existing")

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)

	if gotRequestID != "req-existing" {
		t.Fatalf("request id = %q, want req-existing", gotRequestID)
	}
	if gotTraceID != "trace-existing" {
		t.Fatalf("trace id = %q, want trace-existing", gotTraceID)
	}
	if recorder.Header().Get("X-Request-ID") != "req-existing" {
		t.Fatalf("response request id = %q, want req-existing", recorder.Header().Get("X-Request-ID"))
	}
}

func TestRequestIdentityGeneratesHeadersWhenMissing(t *testing.T) {
	var gotRequestID string
	var gotTraceID string

	handler := RequestIdentity(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotRequestID = GetRequestID(r.Context())
		gotTraceID = GetTraceID(r.Context())
	}))

	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)

	if gotRequestID == "" {
		t.Fatal("request id should be generated")
	}
	if gotTraceID == "" {
		t.Fatal("trace id should be generated")
	}
	if recorder.Header().Get("X-Request-ID") == "" {
		t.Fatal("response X-Request-ID should be present")
	}
}
