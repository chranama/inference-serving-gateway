package upstream

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chranama/inference-serving-gateway/internal/middleware"
	"github.com/chranama/inference-serving-gateway/internal/observability"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
	oteltrace "go.opentelemetry.io/otel/trace"
)

func TestExtractInjectsTraceContextAndCreatesClientSpan(t *testing.T) {
	recorder, provider := newTestSpanRecorder(t)
	defer func() {
		_ = provider.Shutdown(context.Background())
	}()

	var capturedTraceparent string
	var capturedRequestID string
	var capturedTraceID string

	upstreamServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedTraceparent = r.Header.Get("traceparent")
		capturedRequestID = r.Header.Get("X-Request-ID")
		capturedTraceID = r.Header.Get("X-Trace-ID")
		w.Header().Set("X-Trace-ID", capturedTraceID)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer upstreamServer.Close()

	metrics, err := observability.NewMetrics()
	if err != nil {
		t.Fatalf("NewMetrics() error = %v", err)
	}

	client, err := NewClient(upstreamServer.URL, metrics)
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	handler := middleware.Chain(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			response, err := client.Extract(r.Context(), []byte(`{"text":"hello"}`), r.Header.Clone())
			if err != nil {
				t.Fatalf("Extract() error = %v", err)
			}
			w.Header().Set("X-Trace-ID", response.Header.Get("X-Trace-ID"))
			w.WriteHeader(response.StatusCode)
			_, _ = w.Write(response.Body)
		}),
		middleware.RequestIdentity,
		middleware.TraceRequest("extract"),
		middleware.Access(logger, metrics, "extract", client.BaseHost()),
	)

	request := httptest.NewRequest(http.MethodPost, "/v1/extract", nil)
	request.Header.Set("X-Request-ID", "req-2")
	request.Header.Set("X-Trace-ID", "app-trace-2")

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, request)

	if capturedTraceparent == "" {
		t.Fatal("expected traceparent header to be forwarded upstream")
	}
	if capturedRequestID != "req-2" {
		t.Fatalf("captured request id = %q, want req-2", capturedRequestID)
	}
	if capturedTraceID != "app-trace-2" {
		t.Fatalf("captured trace id = %q, want app-trace-2", capturedTraceID)
	}

	serverSpan := findRecordedSpan(t, recorder.Ended(), "gateway.extract")
	clientSpan := findRecordedSpan(t, recorder.Ended(), "upstream.extract")

	if clientSpan.SpanKind() != oteltrace.SpanKindClient {
		t.Fatalf("client span kind = %v, want client", clientSpan.SpanKind())
	}
	if clientSpan.Parent().SpanID() != serverSpan.SpanContext().SpanID() {
		t.Fatalf("client span parent = %s, want %s", clientSpan.Parent().SpanID(), serverSpan.SpanContext().SpanID())
	}
	assertAttrEqual(t, clientSpan.Attributes(), "llm.request_id", "req-2")
	assertAttrEqual(t, clientSpan.Attributes(), "llm.trace_id", "app-trace-2")
	assertAttrEqual(t, clientSpan.Attributes(), "http.response.status_code", int64(http.StatusOK))
	assertUpstreamAttrEqual(t, clientSpan.Attributes(), "server.address", client.BaseHost())
}

func assertUpstreamAttrEqual(t *testing.T, attrs []attribute.KeyValue, key, want string) {
	t.Helper()
	assertAttrEqual(t, attrs, key, want)
}

func newTestSpanRecorder(t *testing.T) (*tracetest.SpanRecorder, *sdktrace.TracerProvider) {
	t.Helper()

	recorder := tracetest.NewSpanRecorder()
	provider := sdktrace.NewTracerProvider()
	provider.RegisterSpanProcessor(recorder)

	otel.SetTracerProvider(provider)
	otel.SetTextMapPropagator(
		propagation.NewCompositeTextMapPropagator(
			propagation.TraceContext{},
			propagation.Baggage{},
		),
	)

	t.Cleanup(func() {
		otel.SetTracerProvider(oteltrace.NewNoopTracerProvider())
		otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator())
	})

	return recorder, provider
}

func findRecordedSpan(t *testing.T, spans []sdktrace.ReadOnlySpan, name string) sdktrace.ReadOnlySpan {
	t.Helper()

	for _, span := range spans {
		if span.Name() == name {
			return span
		}
	}
	t.Fatalf("span %q not found", name)
	return nil
}

func assertAttrEqual(t *testing.T, attrs []attribute.KeyValue, key string, want any) {
	t.Helper()

	for _, attr := range attrs {
		if string(attr.Key) != key {
			continue
		}

		switch expected := want.(type) {
		case string:
			if got := attr.Value.AsString(); got != expected {
				t.Fatalf("%s = %q, want %q", key, got, expected)
			}
			return
		case int64:
			if got := attr.Value.AsInt64(); got != expected {
				t.Fatalf("%s = %d, want %d", key, got, expected)
			}
			return
		default:
			t.Fatalf("unsupported attribute expectation type %T", want)
		}
	}

	t.Fatalf("attribute %q not found", key)
}
