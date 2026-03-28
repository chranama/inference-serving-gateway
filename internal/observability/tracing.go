package observability

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"

	"github.com/chranama/inference-serving-gateway/internal/config"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	sdkresource "go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

type TracingRuntime struct {
	Enabled          bool
	ServiceName      string
	ExporterEndpoint string
	shutdown         func(context.Context) error
}

func (r TracingRuntime) Shutdown(ctx context.Context) error {
	if r.shutdown == nil {
		return nil
	}
	return r.shutdown(ctx)
}

func SetupTracing(ctx context.Context, cfg config.Config, logger *slog.Logger) (TracingRuntime, error) {
	runtime := TracingRuntime{
		Enabled:          false,
		ServiceName:      cfg.OTelServiceName,
		ExporterEndpoint: cfg.OTelExporterOTLPEndpoint,
		shutdown:         func(context.Context) error { return nil },
	}

	otel.SetTextMapPropagator(
		propagation.NewCompositeTextMapPropagator(
			propagation.TraceContext{},
			propagation.Baggage{},
		),
	)

	if !cfg.OTelEnabled {
		logger.Info("otel bootstrap disabled", "service_name", cfg.OTelServiceName)
		return runtime, nil
	}

	if strings.TrimSpace(cfg.OTelExporterOTLPEndpoint) == "" {
		logger.Warn(
			"otel bootstrap enabled but exporter endpoint is empty; running without exporter",
			"service_name", cfg.OTelServiceName,
		)
		return runtime, nil
	}

	exporterOpts, err := otlpHTTPExporterOptions(cfg.OTelExporterOTLPEndpoint)
	if err != nil {
		return runtime, err
	}

	exporter, err := otlptracehttp.New(ctx, exporterOpts...)
	if err != nil {
		return runtime, fmt.Errorf("create OTLP exporter: %w", err)
	}

	resource, err := sdkresource.Merge(
		sdkresource.Default(),
		sdkresource.NewWithAttributes(
			"",
			attribute.String("service.name", cfg.OTelServiceName),
			attribute.String("llm.component", "gateway"),
		),
	)
	if err != nil {
		return runtime, fmt.Errorf("build tracing resource: %w", err)
	}

	provider := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resource),
	)
	otel.SetTracerProvider(provider)

	runtime.Enabled = true
	runtime.shutdown = provider.Shutdown

	logger.Info(
		"otel bootstrap configured",
		"service_name", cfg.OTelServiceName,
		"exporter_endpoint", cfg.OTelExporterOTLPEndpoint,
	)

	return runtime, nil
}

func otlpHTTPExporterOptions(rawEndpoint string) ([]otlptracehttp.Option, error) {
	parsed, err := url.Parse(strings.TrimSpace(rawEndpoint))
	if err != nil {
		return nil, fmt.Errorf("parse OTLP endpoint: %w", err)
	}
	if parsed.Scheme == "" || parsed.Host == "" {
		return nil, fmt.Errorf("OTLP endpoint must be an absolute URL")
	}

	opts := []otlptracehttp.Option{
		otlptracehttp.WithEndpoint(parsed.Host),
	}
	if parsed.Scheme == "http" {
		opts = append(opts, otlptracehttp.WithInsecure())
	}
	if parsed.Path != "" && parsed.Path != "/" {
		opts = append(opts, otlptracehttp.WithURLPath(parsed.Path))
	}

	return opts, nil
}

func Tracer(name string) trace.Tracer {
	return otel.Tracer("inference-serving-gateway/" + name)
}

func GatewayRequestAttributes(routeName, method, path, host, requestID, traceID string) []attribute.KeyValue {
	return []attribute.KeyValue{
		attribute.String("llm.component", "gateway"),
		attribute.String("llm.route", routeName),
		attribute.String("llm.request_id", requestID),
		attribute.String("llm.trace_id", traceID),
		attribute.String("http.request.method", method),
		attribute.String("url.path", path),
		attribute.String("server.address", host),
	}
}

func UpstreamRequestAttributes(routeName, method, path, targetHost, requestID, traceID string) []attribute.KeyValue {
	return []attribute.KeyValue{
		attribute.String("llm.component", "gateway"),
		attribute.String("llm.route", routeName),
		attribute.String("llm.request_id", requestID),
		attribute.String("llm.trace_id", traceID),
		attribute.String("http.request.method", method),
		attribute.String("url.path", path),
		attribute.String("server.address", targetHost),
	}
}

func SetHTTPResponse(span trace.Span, statusCode int, bytesWritten int) {
	if span == nil {
		return
	}

	attrs := []attribute.KeyValue{
		attribute.Int("http.response.status_code", statusCode),
	}
	if bytesWritten >= 0 {
		attrs = append(attrs, attribute.Int("http.response.body.size", bytesWritten))
	}
	span.SetAttributes(attrs...)

	if statusCode >= http.StatusBadRequest {
		span.SetStatus(codes.Error, http.StatusText(statusCode))
		return
	}
	span.SetStatus(codes.Ok, "")
}

func RecordError(span trace.Span, err error) {
	if span == nil || err == nil {
		return
	}
	span.RecordError(err)
	span.SetStatus(codes.Error, err.Error())
}
