package config

import (
	"testing"
	"time"
)

func TestLoadDefaults(t *testing.T) {
	t.Setenv("GATEWAY_UPSTREAM_BASE_URL", "http://localhost:18081")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.ListenAddr != ":8080" {
		t.Fatalf("ListenAddr = %q, want :8080", cfg.ListenAddr)
	}
	if cfg.RequestTimeout != 30*time.Second {
		t.Fatalf("RequestTimeout = %v, want 30s", cfg.RequestTimeout)
	}
	if !cfg.EnableMetrics {
		t.Fatal("EnableMetrics = false, want true")
	}
	if cfg.OTelEnabled {
		t.Fatal("OTelEnabled = true, want false")
	}
	if cfg.OTelServiceName != "inference-serving-gateway" {
		t.Fatalf("OTelServiceName = %q, want inference-serving-gateway", cfg.OTelServiceName)
	}
	if cfg.OTelExporterOTLPEndpoint != "" {
		t.Fatalf("OTelExporterOTLPEndpoint = %q, want empty", cfg.OTelExporterOTLPEndpoint)
	}
	if !cfg.AllowExtract || !cfg.AllowExtractJobs || !cfg.AllowJobStatus {
		t.Fatal("route allowlist defaults should all be enabled")
	}
}

func TestLoadRejectsInvalidURL(t *testing.T) {
	t.Setenv("GATEWAY_UPSTREAM_BASE_URL", "not-a-url")

	if _, err := Load(); err == nil {
		t.Fatal("Load() error = nil, want invalid URL error")
	}
}

func TestLoadOTelOverrides(t *testing.T) {
	t.Setenv("GATEWAY_UPSTREAM_BASE_URL", "http://localhost:18081")
	t.Setenv("GATEWAY_OTEL_ENABLED", "true")
	t.Setenv("GATEWAY_OTEL_SERVICE_NAME", "gateway-dev")
	t.Setenv("GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT", "http://127.0.0.1:4318/v1/traces")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if !cfg.OTelEnabled {
		t.Fatal("OTelEnabled = false, want true")
	}
	if cfg.OTelServiceName != "gateway-dev" {
		t.Fatalf("OTelServiceName = %q, want gateway-dev", cfg.OTelServiceName)
	}
	if cfg.OTelExporterOTLPEndpoint != "http://127.0.0.1:4318/v1/traces" {
		t.Fatalf("OTelExporterOTLPEndpoint = %q, want http://127.0.0.1:4318/v1/traces", cfg.OTelExporterOTLPEndpoint)
	}
}

func TestLoadRejectsInvalidOTLPEndpoint(t *testing.T) {
	t.Setenv("GATEWAY_UPSTREAM_BASE_URL", "http://localhost:18081")
	t.Setenv("GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT", "not-a-url")

	if _, err := Load(); err == nil {
		t.Fatal("Load() error = nil, want invalid OTLP endpoint error")
	}
}
