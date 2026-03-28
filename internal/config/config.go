package config

import (
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	defaultListenAddr             = ":8080"
	defaultRequestTimeout         = 30 * time.Second
	defaultLogLevel               = "info"
	defaultEnableMetrics          = true
	defaultOTelEnabled            = false
	defaultOTelServiceName        = "inference-serving-gateway"
	defaultAllowExtract           = true
	defaultAllowExtractJobs       = true
	defaultAllowJobStatus         = true
	defaultMaxBodyBytes     int64 = 1 << 20
	defaultConcurrencyLimit       = 64
)

// Config contains runtime configuration for the gateway.
type Config struct {
	ListenAddr               string
	UpstreamBaseURL          string
	RequestTimeout           time.Duration
	LogLevel                 string
	EnableMetrics            bool
	OTelEnabled              bool
	OTelServiceName          string
	OTelExporterOTLPEndpoint string
	AllowExtract             bool
	AllowExtractJobs         bool
	AllowJobStatus           bool
	MaxBodyBytes             int64
	ConcurrencyLimit         int
	RateLimitPerSecond       float64
	RateLimitBurst           int
}

// Load reads gateway configuration from environment variables.
func Load() (Config, error) {
	cfg := Config{
		ListenAddr:         defaultListenAddr,
		RequestTimeout:     defaultRequestTimeout,
		LogLevel:           defaultLogLevel,
		EnableMetrics:      defaultEnableMetrics,
		OTelEnabled:        defaultOTelEnabled,
		OTelServiceName:    defaultOTelServiceName,
		AllowExtract:       defaultAllowExtract,
		AllowExtractJobs:   defaultAllowExtractJobs,
		AllowJobStatus:     defaultAllowJobStatus,
		MaxBodyBytes:       defaultMaxBodyBytes,
		ConcurrencyLimit:   defaultConcurrencyLimit,
		RateLimitPerSecond: 0,
		RateLimitBurst:     1,
	}

	cfg.ListenAddr = envString("GATEWAY_LISTEN_ADDR", cfg.ListenAddr)
	cfg.LogLevel = envString("GATEWAY_LOG_LEVEL", cfg.LogLevel)

	upstreamBaseURL := strings.TrimSpace(os.Getenv("GATEWAY_UPSTREAM_BASE_URL"))
	if upstreamBaseURL == "" {
		return Config{}, fmt.Errorf("GATEWAY_UPSTREAM_BASE_URL is required")
	}
	parsedURL, err := url.Parse(upstreamBaseURL)
	if err != nil || parsedURL.Scheme == "" || parsedURL.Host == "" {
		return Config{}, fmt.Errorf("GATEWAY_UPSTREAM_BASE_URL must be a valid absolute URL")
	}
	cfg.UpstreamBaseURL = strings.TrimRight(upstreamBaseURL, "/")

	cfg.RequestTimeout, err = envDuration("GATEWAY_REQUEST_TIMEOUT", cfg.RequestTimeout)
	if err != nil {
		return Config{}, err
	}
	cfg.EnableMetrics, err = envBool("GATEWAY_ENABLE_METRICS", cfg.EnableMetrics)
	if err != nil {
		return Config{}, err
	}
	cfg.OTelEnabled, err = envBool("GATEWAY_OTEL_ENABLED", cfg.OTelEnabled)
	if err != nil {
		return Config{}, err
	}
	cfg.OTelServiceName = envString("GATEWAY_OTEL_SERVICE_NAME", cfg.OTelServiceName)
	cfg.OTelExporterOTLPEndpoint = envString(
		"GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT",
		cfg.OTelExporterOTLPEndpoint,
	)
	cfg.AllowExtract, err = envBool("GATEWAY_ALLOW_EXTRACT", cfg.AllowExtract)
	if err != nil {
		return Config{}, err
	}
	cfg.AllowExtractJobs, err = envBool("GATEWAY_ALLOW_EXTRACT_JOBS", cfg.AllowExtractJobs)
	if err != nil {
		return Config{}, err
	}
	cfg.AllowJobStatus, err = envBool("GATEWAY_ALLOW_JOB_STATUS", cfg.AllowJobStatus)
	if err != nil {
		return Config{}, err
	}
	cfg.MaxBodyBytes, err = envInt64("GATEWAY_MAX_BODY_BYTES", cfg.MaxBodyBytes)
	if err != nil {
		return Config{}, err
	}
	cfg.ConcurrencyLimit, err = envInt("GATEWAY_CONCURRENCY_LIMIT", cfg.ConcurrencyLimit)
	if err != nil {
		return Config{}, err
	}
	cfg.RateLimitPerSecond, err = envFloat("GATEWAY_RATE_LIMIT_PER_SECOND", cfg.RateLimitPerSecond)
	if err != nil {
		return Config{}, err
	}
	cfg.RateLimitBurst, err = envInt("GATEWAY_RATE_LIMIT_BURST", cfg.RateLimitBurst)
	if err != nil {
		return Config{}, err
	}

	if cfg.RequestTimeout <= 0 {
		return Config{}, fmt.Errorf("GATEWAY_REQUEST_TIMEOUT must be positive")
	}
	if cfg.OTelServiceName == "" {
		return Config{}, fmt.Errorf("GATEWAY_OTEL_SERVICE_NAME must not be empty")
	}
	if cfg.OTelExporterOTLPEndpoint != "" {
		parsedOTLPURL, err := url.Parse(cfg.OTelExporterOTLPEndpoint)
		if err != nil || parsedOTLPURL.Scheme == "" || parsedOTLPURL.Host == "" {
			return Config{}, fmt.Errorf("GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT must be a valid absolute URL")
		}
	}
	if cfg.MaxBodyBytes <= 0 {
		return Config{}, fmt.Errorf("GATEWAY_MAX_BODY_BYTES must be positive")
	}
	if cfg.ConcurrencyLimit < 0 {
		return Config{}, fmt.Errorf("GATEWAY_CONCURRENCY_LIMIT must be non-negative")
	}
	if cfg.RateLimitPerSecond < 0 {
		return Config{}, fmt.Errorf("GATEWAY_RATE_LIMIT_PER_SECOND must be non-negative")
	}
	if cfg.RateLimitPerSecond > 0 && cfg.RateLimitBurst <= 0 {
		return Config{}, fmt.Errorf("GATEWAY_RATE_LIMIT_BURST must be positive when rate limiting is enabled")
	}

	return cfg, nil
}

func envString(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func envDuration(key string, fallback time.Duration) (time.Duration, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}
	duration, err := time.ParseDuration(value)
	if err != nil {
		return 0, fmt.Errorf("%s must be a valid duration: %w", key, err)
	}
	return duration, nil
}

func envBool(key string, fallback bool) (bool, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf("%s must be a valid boolean: %w", key, err)
	}
	return parsed, nil
}

func envInt(key string, fallback int) (int, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("%s must be a valid integer: %w", key, err)
	}
	return parsed, nil
}

func envInt64(key string, fallback int64) (int64, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("%s must be a valid integer: %w", key, err)
	}
	return parsed, nil
}

func envFloat(key string, fallback float64) (float64, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return 0, fmt.Errorf("%s must be a valid float: %w", key, err)
	}
	return parsed, nil
}
