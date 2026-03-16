package tests

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/chranama/inference-serving-gateway/internal/config"
	"github.com/chranama/inference-serving-gateway/internal/httpapi"
	"github.com/chranama/inference-serving-gateway/internal/observability"
	"github.com/chranama/inference-serving-gateway/internal/upstream"
)

type extractResponse struct {
	Method    string `json:"method"`
	Path      string `json:"path"`
	RequestID string `json:"request_id"`
	TraceID   string `json:"trace_id"`
	Body      string `json:"body"`
}

type jobSubmitResponse struct {
	JobID     string `json:"job_id"`
	TraceID   string `json:"trace_id"`
	RequestID string `json:"request_id"`
}

type jobStatusResponse struct {
	JobID     string `json:"job_id"`
	TraceID   string `json:"trace_id"`
	RequestID string `json:"request_id"`
	Status    string `json:"status"`
}

func TestHealthz(t *testing.T) {
	gateway, upstreamServer := newGateway(t, nil, newMockUpstream(nil, nil))
	defer gateway.Close()
	defer upstreamServer.Close()

	resp, err := http.Get(gateway.URL + "/healthz")
	if err != nil {
		t.Fatalf("GET /healthz error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
}

func TestReadyzReflectsUpstreamReadiness(t *testing.T) {
	notReadyUpstream := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/readyz" {
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			return
		}
		http.NotFound(w, r)
	})

	gateway, upstreamServer := newGateway(t, nil, notReadyUpstream)
	defer gateway.Close()
	defer upstreamServer.Close()

	resp, err := http.Get(gateway.URL + "/readyz")
	if err != nil {
		t.Fatalf("GET /readyz error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", resp.StatusCode)
	}
}

func TestMetricsEndpointIsExposed(t *testing.T) {
	gateway, upstreamServer := newGateway(t, nil, newMockUpstream(nil, nil))
	defer gateway.Close()
	defer upstreamServer.Close()

	_, _ = http.Get(gateway.URL + "/healthz")

	resp, err := http.Get(gateway.URL + "/metrics")
	if err != nil {
		t.Fatalf("GET /metrics error = %v", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	if !strings.Contains(string(body), "gateway_requests_total") {
		t.Fatalf("/metrics body missing gateway_requests_total")
	}
}

func TestExtractForwardingPreservesHeadersAndBody(t *testing.T) {
	gateway, upstreamServer := newGateway(t, nil, newMockUpstream(nil, nil))
	defer gateway.Close()
	defer upstreamServer.Close()

	requestBody := []byte(`{"schema_id":"demo","text":"hello"}`)
	request, err := http.NewRequest(http.MethodPost, gateway.URL+"/v1/extract", bytes.NewReader(requestBody))
	if err != nil {
		t.Fatalf("NewRequest error = %v", err)
	}
	request.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("POST /v1/extract error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}

	var payload extractResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		t.Fatalf("Decode error = %v", err)
	}

	if payload.Body != string(requestBody) {
		t.Fatalf("body = %q, want %q", payload.Body, requestBody)
	}
	if payload.RequestID == "" || payload.TraceID == "" {
		t.Fatalf("expected request and trace IDs to be propagated, got %+v", payload)
	}
	if resp.Header.Get("X-Request-ID") == "" || resp.Header.Get("X-Trace-ID") == "" {
		t.Fatal("gateway response should expose canonical request and trace IDs")
	}
}

func TestAsyncRoutesPreserveIdentity(t *testing.T) {
	gateway, upstreamServer := newGateway(t, nil, newMockUpstream(nil, nil))
	defer gateway.Close()
	defer upstreamServer.Close()

	submitResp, err := http.Post(gateway.URL+"/v1/extract/jobs", "application/json", strings.NewReader(`{"schema_id":"demo","text":"job"}`))
	if err != nil {
		t.Fatalf("POST /v1/extract/jobs error = %v", err)
	}
	defer submitResp.Body.Close()

	if submitResp.StatusCode != http.StatusAccepted {
		t.Fatalf("submit status = %d, want 202", submitResp.StatusCode)
	}

	var submitted jobSubmitResponse
	if err := json.NewDecoder(submitResp.Body).Decode(&submitted); err != nil {
		t.Fatalf("Decode submit response error = %v", err)
	}

	statusResp, err := http.Get(gateway.URL + "/v1/extract/jobs/" + submitted.JobID)
	if err != nil {
		t.Fatalf("GET /v1/extract/jobs/{job_id} error = %v", err)
	}
	defer statusResp.Body.Close()

	var statusPayload jobStatusResponse
	if err := json.NewDecoder(statusResp.Body).Decode(&statusPayload); err != nil {
		t.Fatalf("Decode status response error = %v", err)
	}

	if statusPayload.JobID != submitted.JobID {
		t.Fatalf("job id = %q, want %q", statusPayload.JobID, submitted.JobID)
	}
	if statusPayload.TraceID == "" {
		t.Fatal("trace id should be preserved through async status polling")
	}
}

func TestTimeoutReturnsGatewayTimeout(t *testing.T) {
	gateway, upstreamServer := newGateway(t, func(cfg *config.Config) {
		cfg.RequestTimeout = 50 * time.Millisecond
	}, newMockUpstream(nil, nil))
	defer gateway.Close()
	defer upstreamServer.Close()

	request, err := http.NewRequest(http.MethodPost, gateway.URL+"/v1/extract", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("NewRequest error = %v", err)
	}
	request.Header.Set("X-Test-Behavior", "slow")

	resp, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("POST /v1/extract error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusGatewayTimeout {
		t.Fatalf("status = %d, want 504", resp.StatusCode)
	}
}

func TestUpstreamUnavailableReturnsServiceUnavailable(t *testing.T) {
	cfg := baseConfig()
	cfg.UpstreamBaseURL = unusedBaseURL(t)

	gateway := newGatewayWithConfig(t, cfg)
	defer gateway.Close()

	resp, err := http.Post(gateway.URL+"/v1/extract", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("POST /v1/extract error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", resp.StatusCode)
	}
}

func TestRequestTooLarge(t *testing.T) {
	gateway, upstreamServer := newGateway(t, func(cfg *config.Config) {
		cfg.MaxBodyBytes = 4
	}, newMockUpstream(nil, nil))
	defer gateway.Close()
	defer upstreamServer.Close()

	resp, err := http.Post(gateway.URL+"/v1/extract", "application/json", strings.NewReader(`{"too":"large"}`))
	if err != nil {
		t.Fatalf("POST /v1/extract error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413", resp.StatusCode)
	}
}

func TestRouteNotAllowed(t *testing.T) {
	gateway, upstreamServer := newGateway(t, func(cfg *config.Config) {
		cfg.AllowExtract = false
	}, newMockUpstream(nil, nil))
	defer gateway.Close()
	defer upstreamServer.Close()

	resp, err := http.Post(gateway.URL+"/v1/extract", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("POST /v1/extract error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", resp.StatusCode)
	}
}

func TestConcurrencyLimitRejectsSecondRequest(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})

	gateway, upstreamServer := newGateway(t, func(cfg *config.Config) {
		cfg.ConcurrencyLimit = 1
	}, newMockUpstream(started, release))
	defer gateway.Close()
	defer upstreamServer.Close()

	var wg sync.WaitGroup
	wg.Add(1)

	go func() {
		defer wg.Done()

		request, err := http.NewRequest(http.MethodPost, gateway.URL+"/v1/extract", strings.NewReader(`{}`))
		if err != nil {
			t.Errorf("NewRequest error = %v", err)
			return
		}
		request.Header.Set("X-Test-Behavior", "block")

		resp, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Errorf("first request error = %v", err)
			return
		}
		defer resp.Body.Close()
	}()

	<-started

	resp, err := http.Post(gateway.URL+"/v1/extract", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("second request error = %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", resp.StatusCode)
	}

	close(release)
	wg.Wait()
}

func TestRateLimitRejectsBurst(t *testing.T) {
	gateway, upstreamServer := newGateway(t, func(cfg *config.Config) {
		cfg.RateLimitPerSecond = 1
		cfg.RateLimitBurst = 1
	}, newMockUpstream(nil, nil))
	defer gateway.Close()
	defer upstreamServer.Close()

	first, err := http.Post(gateway.URL+"/v1/extract", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("first request error = %v", err)
	}
	first.Body.Close()

	second, err := http.Post(gateway.URL+"/v1/extract", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("second request error = %v", err)
	}
	defer second.Body.Close()

	if second.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want 429", second.StatusCode)
	}
}

func baseConfig() config.Config {
	return config.Config{
		ListenAddr:         ":0",
		UpstreamBaseURL:    "http://127.0.0.1:18081",
		RequestTimeout:     300 * time.Millisecond,
		LogLevel:           "error",
		EnableMetrics:      true,
		AllowExtract:       true,
		AllowExtractJobs:   true,
		AllowJobStatus:     true,
		MaxBodyBytes:       1 << 20,
		ConcurrencyLimit:   64,
		RateLimitPerSecond: 0,
		RateLimitBurst:     1,
	}
}

func newGateway(t *testing.T, mutate func(*config.Config), upstreamHandler http.Handler) (*httptest.Server, *httptest.Server) {
	t.Helper()

	cfg := baseConfig()
	if mutate != nil {
		mutate(&cfg)
	}

	upstreamServer := httptest.NewServer(upstreamHandler)
	cfg.UpstreamBaseURL = upstreamServer.URL

	return newGatewayWithConfig(t, cfg), upstreamServer
}

func newGatewayWithConfig(t *testing.T, cfg config.Config) *httptest.Server {
	t.Helper()

	metrics, err := observability.NewMetrics()
	if err != nil {
		t.Fatalf("NewMetrics error = %v", err)
	}

	logger, err := observability.NewLogger(cfg.LogLevel)
	if err != nil {
		t.Fatalf("NewLogger error = %v", err)
	}

	upstreamClient, err := upstream.NewClient(cfg.UpstreamBaseURL, metrics)
	if err != nil {
		t.Fatalf("NewClient error = %v", err)
	}

	return httptest.NewServer(httpapi.NewHandler(cfg, logger, metrics, upstreamClient))
}

func newMockUpstream(started chan<- struct{}, release <-chan struct{}) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})

	mux.HandleFunc("/v1/extract", func(w http.ResponseWriter, r *http.Request) {
		if started != nil && r.Header.Get("X-Test-Behavior") == "block" {
			select {
			case started <- struct{}{}:
			default:
			}
			<-release
		}
		if r.Header.Get("X-Test-Behavior") == "slow" {
			time.Sleep(100 * time.Millisecond)
		}

		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("X-Trace-ID", r.Header.Get("X-Trace-ID"))
		writeJSON(w, http.StatusOK, extractResponse{
			Method:    r.Method,
			Path:      r.URL.Path,
			RequestID: r.Header.Get("X-Request-ID"),
			TraceID:   r.Header.Get("X-Trace-ID"),
			Body:      string(body),
		})
	})

	mux.HandleFunc("/v1/extract/jobs", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("X-Trace-ID", r.Header.Get("X-Trace-ID"))
		writeJSON(w, http.StatusAccepted, jobSubmitResponse{
			JobID:     "job-123",
			TraceID:   r.Header.Get("X-Trace-ID"),
			RequestID: r.Header.Get("X-Request-ID"),
		})
	})

	mux.HandleFunc("/v1/extract/jobs/", func(w http.ResponseWriter, r *http.Request) {
		jobID := strings.TrimPrefix(r.URL.Path, "/v1/extract/jobs/")
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("X-Trace-ID", r.Header.Get("X-Trace-ID"))
		writeJSON(w, http.StatusOK, jobStatusResponse{
			JobID:     jobID,
			TraceID:   r.Header.Get("X-Trace-ID"),
			RequestID: r.Header.Get("X-Request-ID"),
			Status:    "succeeded",
		})
	})

	return mux
}

func unusedBaseURL(t *testing.T) string {
	t.Helper()

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("Listen error = %v", err)
	}
	defer listener.Close()

	return fmt.Sprintf("http://%s", listener.Addr().String())
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
