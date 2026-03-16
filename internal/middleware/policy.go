package middleware

import (
	"net/http"

	edgeerrors "github.com/chranama/inference-serving-gateway/internal/errors"
	"github.com/chranama/inference-serving-gateway/internal/observability"
)

// RoutePolicy enforces a coarse route allow/deny decision.
func RoutePolicy(allowed bool, metrics *observability.Metrics) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !allowed {
				metrics.IncEdgeError("route_not_allowed")
				edgeerrors.WriteJSON(w, http.StatusForbidden, "route_not_allowed", "route is not allowed by gateway policy", GetRequestID(r.Context()))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
