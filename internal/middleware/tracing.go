package middleware

import (
	"net/http"

	"github.com/chranama/inference-serving-gateway/internal/observability"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

// TraceRequest creates a gateway server span while preserving application identity fields.
func TraceRequest(routeName string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestID := GetRequestID(r.Context())
			traceID := GetTraceID(r.Context())

			parentCtx := otel.GetTextMapPropagator().Extract(
				r.Context(),
				propagation.HeaderCarrier(r.Header),
			)

			ctx, span := observability.Tracer("http.server").Start(
				parentCtx,
				"gateway."+routeName,
				trace.WithSpanKind(trace.SpanKindServer),
				trace.WithAttributes(
					observability.GatewayRequestAttributes(
						routeName,
						r.Method,
						r.URL.Path,
						r.Host,
						requestID,
						traceID,
					)...,
				),
			)
			defer span.End()

			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
