package policy

import (
	"testing"

	"github.com/chranama/inference-serving-gateway/internal/config"
)

func TestAllowlist(t *testing.T) {
	allowlist := NewAllowlist(config.Config{
		AllowExtract:     true,
		AllowExtractJobs: false,
		AllowJobStatus:   true,
	})

	if !allowlist.Allowed(RouteExtract) {
		t.Fatal("extract should be allowed")
	}
	if allowlist.Allowed(RouteExtractJobs) {
		t.Fatal("extract jobs should be blocked")
	}
	if !allowlist.Allowed(RouteJobStatus) {
		t.Fatal("job status should be allowed")
	}
}
