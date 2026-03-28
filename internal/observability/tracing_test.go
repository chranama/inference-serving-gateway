package observability

import (
	"context"
	"io"
	"log/slog"
	"testing"

	"github.com/chranama/inference-serving-gateway/internal/config"
)

func TestSetupTracingDisabledIsNoop(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	runtime, err := SetupTracing(context.Background(), config.Config{
		OTelEnabled:              false,
		OTelServiceName:          "gateway-test",
		OTelExporterOTLPEndpoint: "",
	}, logger)
	if err != nil {
		t.Fatalf("SetupTracing() error = %v", err)
	}
	if runtime.Enabled {
		t.Fatal("TracingRuntime.Enabled = true, want false")
	}
	if err := runtime.Shutdown(context.Background()); err != nil {
		t.Fatalf("TracingRuntime.Shutdown() error = %v", err)
	}
}

func TestSetupTracingMissingEndpointIsNoop(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	runtime, err := SetupTracing(context.Background(), config.Config{
		OTelEnabled:              true,
		OTelServiceName:          "gateway-test",
		OTelExporterOTLPEndpoint: "",
	}, logger)
	if err != nil {
		t.Fatalf("SetupTracing() error = %v", err)
	}
	if runtime.Enabled {
		t.Fatal("TracingRuntime.Enabled = true, want false")
	}
}

func TestOTLPHTTPExporterOptionsParsesEndpoint(t *testing.T) {
	opts, err := otlpHTTPExporterOptions("http://127.0.0.1:4318/v1/traces")
	if err != nil {
		t.Fatalf("otlpHTTPExporterOptions() error = %v", err)
	}
	if len(opts) == 0 {
		t.Fatal("otlpHTTPExporterOptions() returned no options")
	}
}
