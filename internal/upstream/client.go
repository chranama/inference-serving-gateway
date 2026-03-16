package upstream

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/chranama/inference-serving-gateway/internal/observability"
)

var (
	// ErrTimeout indicates the upstream call timed out.
	ErrTimeout = errors.New("upstream timeout")
	// ErrUnavailable indicates the upstream call failed for a non-timeout transport reason.
	ErrUnavailable = errors.New("upstream unavailable")
)

// Response is a materialized upstream HTTP response.
type Response struct {
	StatusCode int
	Header     http.Header
	Body       []byte
}

// Client is a small wrapper around http.Client for gateway forwarding.
type Client struct {
	baseURL    *url.URL
	httpClient *http.Client
	metrics    *observability.Metrics
}

// NewClient constructs an upstream client from a base URL.
func NewClient(baseURL string, metrics *observability.Metrics) (*Client, error) {
	parsed, err := url.Parse(strings.TrimRight(baseURL, "/"))
	if err != nil {
		return nil, fmt.Errorf("parse upstream base URL: %w", err)
	}

	return &Client{
		baseURL: parsed,
		httpClient: &http.Client{
			Transport: http.DefaultTransport,
		},
		metrics: metrics,
	}, nil
}

// BaseHost returns the configured upstream host for logging.
func (c *Client) BaseHost() string {
	return c.baseURL.Host
}

// CheckReady verifies that the upstream readyz endpoint returns a 2xx status.
func (c *Client) CheckReady(ctx context.Context) error {
	resp, err := c.forward(ctx, "readyz", http.MethodGet, "/readyz", nil, http.Header{})
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("%w: readyz returned status %d", ErrUnavailable, resp.StatusCode)
	}
	return nil
}

// Extract forwards a sync extract request.
func (c *Client) Extract(ctx context.Context, body []byte, headers http.Header) (*Response, error) {
	return c.forward(ctx, "extract", http.MethodPost, "/v1/extract", body, headers)
}

// SubmitJob forwards an async extract submit request.
func (c *Client) SubmitJob(ctx context.Context, body []byte, headers http.Header) (*Response, error) {
	return c.forward(ctx, "extract_jobs", http.MethodPost, "/v1/extract/jobs", body, headers)
}

// GetJobStatus forwards an async extract status request.
func (c *Client) GetJobStatus(ctx context.Context, jobID string, headers http.Header) (*Response, error) {
	return c.forward(ctx, "job_status", http.MethodGet, "/v1/extract/jobs/"+jobID, nil, headers)
}

func (c *Client) forward(ctx context.Context, routeName, method, path string, body []byte, headers http.Header) (*Response, error) {
	target := c.baseURL.ResolveReference(&url.URL{Path: path})
	req, err := http.NewRequestWithContext(ctx, method, target.String(), bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("build upstream request: %w", err)
	}

	copyHeaders(req.Header, headers)
	req.Header.Set("X-Gateway-Proxy", "inference-serving-gateway")

	start := time.Now()
	resp, err := c.httpClient.Do(req)
	if err != nil {
		duration := time.Since(start)
		result := "unavailable"
		if isTimeoutError(err) {
			result = "timeout"
			c.metrics.ObserveUpstreamRequest(routeName, method, result, duration)
			return nil, ErrTimeout
		}
		c.metrics.ObserveUpstreamRequest(routeName, method, result, duration)
		return nil, ErrUnavailable
	}
	defer resp.Body.Close()

	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		duration := time.Since(start)
		c.metrics.ObserveUpstreamRequest(routeName, method, "unavailable", duration)
		return nil, ErrUnavailable
	}

	duration := time.Since(start)
	c.metrics.ObserveUpstreamRequest(routeName, method, fmt.Sprintf("%d", resp.StatusCode), duration)

	return &Response{
		StatusCode: resp.StatusCode,
		Header:     resp.Header.Clone(),
		Body:       responseBody,
	}, nil
}

func copyHeaders(target, source http.Header) {
	for key, values := range source {
		for _, value := range values {
			target.Add(key, value)
		}
	}
}

func isTimeoutError(err error) bool {
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}

	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
}
