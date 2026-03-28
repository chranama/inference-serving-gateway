package middleware

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/chranama/inference-serving-gateway/internal/observability"
	"go.opentelemetry.io/otel/trace"
)

type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func (r *statusRecorder) Write(body []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	count, err := r.ResponseWriter.Write(body)
	r.bytes += count
	return count, err
}

// Access logs structured request metadata and records edge metrics.
func Access(logger *slog.Logger, metrics *observability.Metrics, routeName, upstreamHost string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			recorder := &statusRecorder{ResponseWriter: w}

			next.ServeHTTP(recorder, r)

			status := recorder.status
			if status == 0 {
				status = http.StatusOK
			}

			duration := time.Since(start)
			metrics.ObserveEdgeRequest(routeName, r.Method, status, duration)
			observability.SetHTTPResponse(trace.SpanFromContext(r.Context()), status, recorder.bytes)

			logger.Info("gateway request",
				"request_id", GetRequestID(r.Context()),
				"trace_id", GetTraceID(r.Context()),
				"route", routeName,
				"method", r.Method,
				"status_code", status,
				"latency_ms", duration.Milliseconds(),
				"bytes_written", recorder.bytes,
				"upstream_host", upstreamHost,
			)
		})
	}
}
