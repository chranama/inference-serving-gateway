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
