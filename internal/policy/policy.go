package policy

import "github.com/chranama/inference-serving-gateway/internal/config"

// Route names used by allowlist decisions.
const (
	RouteExtract     = "extract"
	RouteExtractJobs = "extract_jobs"
	RouteJobStatus   = "job_status"
	RouteHealthz     = "healthz"
	RouteReadyz      = "readyz"
	RouteMetrics     = "metrics"
	RouteUnsupported = "unsupported_route"
)

// Allowlist contains coarse route-level edge policy.
type Allowlist struct {
	allowExtract     bool
	allowExtractJobs bool
	allowJobStatus   bool
}

// NewAllowlist builds an allowlist from runtime config.
func NewAllowlist(cfg config.Config) *Allowlist {
	return &Allowlist{
		allowExtract:     cfg.AllowExtract,
		allowExtractJobs: cfg.AllowExtractJobs,
		allowJobStatus:   cfg.AllowJobStatus,
	}
}

// Allowed reports whether the named route is edge-allowed.
func (a *Allowlist) Allowed(route string) bool {
	switch route {
	case RouteExtract:
		return a.allowExtract
	case RouteExtractJobs:
		return a.allowExtractJobs
	case RouteJobStatus:
		return a.allowJobStatus
	default:
		return true
	}
}
