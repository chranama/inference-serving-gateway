package middleware

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chranama/inference-serving-gateway/internal/observability"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
	oteltrace "go.opentelemetry.io/otel/trace"
)

func TestTraceRequestCreatesGatewayServerSpan(t *testing.T) {
	recorder, provider := newTestSpanRecorder(t)
	defer func() {
		_ = provider.Shutdown(context.Background())
	}()

	parentCtx, parentSpan := otel.Tracer("test").Start(context.Background(), "parent")

	metrics, err := observability.NewMetrics()
	if err != nil {
		t.Fatalf("NewMetrics() error = %v", err)
	}

	handler := Chain(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusAccepted)
			_, _ = w.Write([]byte("ok"))
		}),
		RequestIdentity,
		TraceRequest("extract"),
		Access(slog.New(slog.NewTextHandler(io.Discard, nil)), metrics, "extract", "backend.local"),
	)

	request := httptest.NewRequest(http.MethodPost, "/v1/extract", nil)
	request.Header.Set("X-Request-ID", "req-1")
	request.Header.Set("X-Trace-ID", "app-trace-1")
	otel.GetTextMapPropagator().Inject(parentCtx, propagation.HeaderCarrier(request.Header))

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, request)
	parentSpan.End()

	span := findRecordedSpan(t, recorder.Ended(), "gateway.extract")
	if span.SpanKind() != oteltrace.SpanKindServer {
		t.Fatalf("span kind = %v, want server", span.SpanKind())
	}
	if got := span.Parent().SpanID(); got != parentSpan.SpanContext().SpanID() {
		t.Fatalf("parent span id = %s, want %s", got, parentSpan.SpanContext().SpanID())
	}
	assertAttrEqual(t, span.Attributes(), "llm.request_id", "req-1")
	assertAttrEqual(t, span.Attributes(), "llm.trace_id", "app-trace-1")
	assertAttrEqual(t, span.Attributes(), "llm.route", "extract")
	assertAttrEqual(t, span.Attributes(), "http.request.method", http.MethodPost)
	assertAttrEqual(t, span.Attributes(), "url.path", "/v1/extract")
	assertAttrEqual(t, span.Attributes(), "http.response.status_code", int64(http.StatusAccepted))
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
