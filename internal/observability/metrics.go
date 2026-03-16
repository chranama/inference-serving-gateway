package observability

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Metrics contains gateway metrics and the registry that owns them.
type Metrics struct {
	registry                *prometheus.Registry
	requestsTotal           *prometheus.CounterVec
	requestDurationSeconds  *prometheus.HistogramVec
	upstreamRequestsTotal   *prometheus.CounterVec
	upstreamDurationSeconds *prometheus.HistogramVec
	edgeErrorsTotal         *prometheus.CounterVec
}

// NewMetrics constructs the Prometheus metrics set used by the gateway.
func NewMetrics() (*Metrics, error) {
	registry := prometheus.NewRegistry()

	m := &Metrics{
		registry: registry,
		requestsTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "gateway_requests_total",
			Help: "Total HTTP requests handled by the gateway.",
		}, []string{"route", "method", "status"}),
		requestDurationSeconds: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "gateway_request_duration_seconds",
			Help:    "Latency for gateway-handled HTTP requests.",
			Buckets: prometheus.DefBuckets,
		}, []string{"route", "method"}),
		upstreamRequestsTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "gateway_upstream_requests_total",
			Help: "Total upstream requests attempted by the gateway.",
		}, []string{"route", "method", "result"}),
		upstreamDurationSeconds: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "gateway_upstream_request_duration_seconds",
			Help:    "Latency for upstream requests made by the gateway.",
			Buckets: prometheus.DefBuckets,
		}, []string{"route", "method", "result"}),
		edgeErrorsTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "gateway_edge_errors_total",
			Help: "Total edge-owned rejections and errors emitted by the gateway.",
		}, []string{"code"}),
	}

	if err := registry.Register(m.requestsTotal); err != nil {
		return nil, err
	}
	if err := registry.Register(m.requestDurationSeconds); err != nil {
		return nil, err
	}
	if err := registry.Register(m.upstreamRequestsTotal); err != nil {
		return nil, err
	}
	if err := registry.Register(m.upstreamDurationSeconds); err != nil {
		return nil, err
	}
	if err := registry.Register(m.edgeErrorsTotal); err != nil {
		return nil, err
	}

	return m, nil
}

// Handler returns the Prometheus metrics handler.
func (m *Metrics) Handler() http.Handler {
	return promhttp.HandlerFor(m.registry, promhttp.HandlerOpts{})
}

// ObserveEdgeRequest records request-level gateway metrics.
func (m *Metrics) ObserveEdgeRequest(route, method string, status int, duration time.Duration) {
	if m == nil {
		return
	}

	statusLabel := strconv.Itoa(status)
	m.requestsTotal.WithLabelValues(route, method, statusLabel).Inc()
	m.requestDurationSeconds.WithLabelValues(route, method).Observe(duration.Seconds())
}

// ObserveUpstreamRequest records upstream request latency and result.
func (m *Metrics) ObserveUpstreamRequest(route, method, result string, duration time.Duration) {
	if m == nil {
		return
	}

	m.upstreamRequestsTotal.WithLabelValues(route, method, result).Inc()
	m.upstreamDurationSeconds.WithLabelValues(route, method, result).Observe(duration.Seconds())
}

// IncEdgeError increments the edge error counter for the given code.
func (m *Metrics) IncEdgeError(code string) {
	if m == nil {
		return
	}
	m.edgeErrorsTotal.WithLabelValues(code).Inc()
}
