package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/chranama/inference-serving-gateway/internal/config"
	edgeerrors "github.com/chranama/inference-serving-gateway/internal/errors"
	"github.com/chranama/inference-serving-gateway/internal/health"
	"github.com/chranama/inference-serving-gateway/internal/limiter"
	"github.com/chranama/inference-serving-gateway/internal/middleware"
	"github.com/chranama/inference-serving-gateway/internal/observability"
	"github.com/chranama/inference-serving-gateway/internal/policy"
	"github.com/chranama/inference-serving-gateway/internal/upstream"
)

type routeOptions struct {
	allowRoute string
	timeout    bool
	admission  bool
}

// Server owns the HTTP handler graph for the gateway.
type Server struct {
	cfg                config.Config
	logger             *slog.Logger
	metrics            *observability.Metrics
	upstreamClient     *upstream.Client
	readyChecker       health.Checker
	allowlist          *policy.Allowlist
	concurrencyLimit   *limiter.ConcurrencyLimiter
	metricsHandler     http.Handler
	rateLimiter        http.Handler
	rateLimiterMW      func(http.Handler) http.Handler
	concurrencyLimitMW func(http.Handler) http.Handler
}

// NewHandler constructs the top-level HTTP handler for the gateway.
func NewHandler(cfg config.Config, logger *slog.Logger, metrics *observability.Metrics, upstreamClient *upstream.Client) http.Handler {
	server := &Server{
		cfg:                cfg,
		logger:             logger,
		metrics:            metrics,
		upstreamClient:     upstreamClient,
		readyChecker:       health.NewUpstreamChecker(upstreamClient),
		allowlist:          policy.NewAllowlist(cfg),
		concurrencyLimit:   limiter.NewConcurrencyLimiter(cfg.ConcurrencyLimit),
		metricsHandler:     metrics.Handler(),
		rateLimiterMW:      middleware.RateLimit(limiter.NewRateLimiter(cfg.RateLimitPerSecond, cfg.RateLimitBurst), metrics),
		concurrencyLimitMW: middleware.ConcurrencyLimit(limiter.NewConcurrencyLimiter(cfg.ConcurrencyLimit), metrics),
	}

	mux := http.NewServeMux()
	mux.Handle("GET /healthz", server.wrap(policy.RouteHealthz, http.HandlerFunc(server.handleHealthz), routeOptions{}))
	mux.Handle("GET /readyz", server.wrap(policy.RouteReadyz, http.HandlerFunc(server.handleReadyz), routeOptions{timeout: true}))
	if cfg.EnableMetrics {
		mux.Handle("GET /metrics", server.wrap(policy.RouteMetrics, server.metricsHandler, routeOptions{}))
	}
	mux.Handle("POST /v1/extract", server.wrap(policy.RouteExtract, http.HandlerFunc(server.handleExtract), routeOptions{
		allowRoute: policy.RouteExtract,
		timeout:    true,
		admission:  true,
	}))
	mux.Handle("POST /v1/extract/jobs", server.wrap(policy.RouteExtractJobs, http.HandlerFunc(server.handleSubmitJob), routeOptions{
		allowRoute: policy.RouteExtractJobs,
		timeout:    true,
		admission:  true,
	}))
	mux.Handle("GET /v1/extract/jobs/{job_id}", server.wrap(policy.RouteJobStatus, http.HandlerFunc(server.handleGetJobStatus), routeOptions{
		allowRoute: policy.RouteJobStatus,
		timeout:    true,
		admission:  true,
	}))
	mux.Handle("/", server.wrap(policy.RouteUnsupported, http.HandlerFunc(server.handleUnsupported), routeOptions{}))

	return mux
}

func (s *Server) wrap(routeName string, handler http.Handler, options routeOptions) http.Handler {
	middlewares := []func(http.Handler) http.Handler{
		middleware.RequestIdentity,
		middleware.Access(s.logger, s.metrics, routeName, s.upstreamClient.BaseHost()),
	}

	if options.allowRoute != "" {
		middlewares = append(middlewares, middleware.RoutePolicy(s.allowlist.Allowed(options.allowRoute), s.metrics))
	}
	if options.admission {
		middlewares = append(middlewares, s.rateLimiterMW, s.concurrencyLimitMW)
	}
	if options.timeout {
		middlewares = append(middlewares, middleware.Timeout(s.cfg.RequestTimeout))
	}

	return middleware.Chain(handler, middlewares...)
}

func (s *Server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleReadyz(w http.ResponseWriter, r *http.Request) {
	if err := s.readyChecker.Check(r.Context()); err != nil {
		s.writeEdgeError(w, r, http.StatusServiceUnavailable, "upstream_unavailable", "upstream readiness check failed")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *Server) handleUnsupported(w http.ResponseWriter, r *http.Request) {
	s.writeEdgeError(w, r, http.StatusNotFound, "unsupported_route", "unsupported route")
}

func (s *Server) handleExtract(w http.ResponseWriter, r *http.Request) {
	body, ok := s.readBoundedBody(w, r)
	if !ok {
		return
	}

	response, err := s.upstreamClient.Extract(r.Context(), body, r.Header.Clone())
	if err != nil {
		s.writeUpstreamError(w, r, err)
		return
	}

	s.writeUpstreamResponse(w, r, response)
}

func (s *Server) handleSubmitJob(w http.ResponseWriter, r *http.Request) {
	body, ok := s.readBoundedBody(w, r)
	if !ok {
		return
	}

	response, err := s.upstreamClient.SubmitJob(r.Context(), body, r.Header.Clone())
	if err != nil {
		s.writeUpstreamError(w, r, err)
		return
	}

	s.writeUpstreamResponse(w, r, response)
}

func (s *Server) handleGetJobStatus(w http.ResponseWriter, r *http.Request) {
	jobID := strings.TrimSpace(r.PathValue("job_id"))
	if jobID == "" {
		s.writeEdgeError(w, r, http.StatusBadRequest, "invalid_request", "job_id is required")
		return
	}

	response, err := s.upstreamClient.GetJobStatus(r.Context(), jobID, r.Header.Clone())
	if err != nil {
		s.writeUpstreamError(w, r, err)
		return
	}

	s.writeUpstreamResponse(w, r, response)
}

func (s *Server) readBoundedBody(w http.ResponseWriter, r *http.Request) ([]byte, bool) {
	r.Body = http.MaxBytesReader(w, r.Body, s.cfg.MaxBodyBytes)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			s.writeEdgeError(w, r, http.StatusRequestEntityTooLarge, "request_too_large", "request body exceeds gateway limit")
			return nil, false
		}

		s.writeEdgeError(w, r, http.StatusBadRequest, "invalid_request", "failed to read request body")
		return nil, false
	}

	return body, true
}

func (s *Server) writeUpstreamError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, upstream.ErrTimeout):
		s.writeEdgeError(w, r, http.StatusGatewayTimeout, "upstream_timeout", "upstream request timed out")
	default:
		s.writeEdgeError(w, r, http.StatusServiceUnavailable, "upstream_unavailable", "upstream request failed")
	}
}

func (s *Server) writeUpstreamResponse(w http.ResponseWriter, r *http.Request, response *upstream.Response) {
	copyResponseHeaders(w.Header(), response.Header)

	requestID := middleware.GetRequestID(r.Context())
	traceID := response.Header.Get("X-Trace-ID")
	if traceID == "" {
		traceID = middleware.GetTraceID(r.Context())
	}

	w.Header().Set("X-Request-ID", requestID)
	if traceID != "" {
		w.Header().Set("X-Trace-ID", traceID)
	}

	w.WriteHeader(response.StatusCode)
	_, _ = w.Write(response.Body)
}

func (s *Server) writeEdgeError(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	s.metrics.IncEdgeError(code)
	edgeerrors.WriteJSON(w, status, code, message, middleware.GetRequestID(r.Context()))
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func copyResponseHeaders(target, source http.Header) {
	for key, values := range source {
		switch http.CanonicalHeaderKey(key) {
		case "Connection", "Keep-Alive", "Proxy-Authenticate", "Proxy-Authorization", "Te", "Trailer", "Transfer-Encoding", "Upgrade", "Content-Length":
			continue
		}

		for _, value := range values {
			target.Add(key, value)
		}
	}
}
