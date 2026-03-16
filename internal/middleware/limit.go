package middleware

import (
	"net/http"

	edgeerrors "github.com/chranama/inference-serving-gateway/internal/errors"
	"github.com/chranama/inference-serving-gateway/internal/limiter"
	"github.com/chranama/inference-serving-gateway/internal/observability"
	"golang.org/x/time/rate"
)

// ConcurrencyLimit rejects requests when the global in-flight cap is exhausted.
func ConcurrencyLimit(limit *limiter.ConcurrencyLimiter, metrics *observability.Metrics) func(http.Handler) http.Handler {
	if limit == nil {
		return func(next http.Handler) http.Handler { return next }
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !limit.TryAcquire() {
				metrics.IncEdgeError("concurrency_limited")
				edgeerrors.WriteJSON(w, http.StatusServiceUnavailable, "concurrency_limited", "global concurrency limit reached", GetRequestID(r.Context()))
				return
			}
			defer limit.Release()

			next.ServeHTTP(w, r)
		})
	}
}

// RateLimit rejects requests when the token bucket does not have capacity.
func RateLimit(rateLimiter *rate.Limiter, metrics *observability.Metrics) func(http.Handler) http.Handler {
	if rateLimiter == nil {
		return func(next http.Handler) http.Handler { return next }
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !rateLimiter.Allow() {
				metrics.IncEdgeError("rate_limited")
				edgeerrors.WriteJSON(w, http.StatusTooManyRequests, "rate_limited", "rate limit exceeded", GetRequestID(r.Context()))
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
