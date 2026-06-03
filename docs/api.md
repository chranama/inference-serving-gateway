# API

The gateway exposes extraction, health, readiness, and metrics endpoints. It
forwards accepted extraction requests to the configured upstream backend.

## Runtime Endpoints

| Method | Path | Behavior |
|---|---|---|
| `GET` | `/healthz` | Returns gateway liveness. Does not require upstream readiness. |
| `GET` | `/readyz` | Calls upstream `/readyz` and returns ready only when the backend is reachable. |
| `GET` | `/metrics` | Returns Prometheus metrics when metrics are enabled. |
| `POST` | `/v1/extract` | Forwards a synchronous extraction request to the backend. |
| `POST` | `/v1/extract/jobs` | Forwards asynchronous extraction submission to the backend. |
| `GET` | `/v1/extract/jobs/{job_id}` | Forwards asynchronous job-status polling to the backend. |

Unsupported routes return an edge-owned `unsupported_route` error.

## Identity Headers

The gateway preserves client-provided identity headers when present:

- `X-Request-ID`
- `X-Trace-ID`

When either header is missing, the gateway assigns one. Responses include the
gateway request id and the effective trace id.

The gateway also sends:

- `X-Gateway-Proxy: inference-serving-gateway`

to the upstream backend so the backend can identify gateway-routed traffic.

## OpenTelemetry

When OpenTelemetry is enabled, the gateway creates server spans for incoming
requests and client spans for upstream calls. It injects W3C trace context into
the forwarded upstream request.

Configuration:

- `GATEWAY_OTEL_ENABLED`
- `GATEWAY_OTEL_SERVICE_NAME`
- `GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT`

## Edge-Owned Errors

The gateway returns structured JSON errors for edge-owned failures.

| Code | Typical Status | Cause |
|---|---:|---|
| `invalid_request` | `400` | The gateway cannot read a request body or required route parameter. |
| `unsupported_route` | `404` | The route is not served by the gateway. |
| `request_too_large` | `413` | Request body exceeds `GATEWAY_MAX_BODY_BYTES`. |
| `route_not_allowed` | `403` | Route is disabled by gateway route policy. |
| `rate_limited` | `429` | Request exceeds configured rate limit. |
| `concurrency_limited` | `503` | Request exceeds configured concurrency limit. |
| `upstream_timeout` | `504` | Upstream request timed out. |
| `upstream_unavailable` | `503` | Upstream readiness or forwarding failed. |

Backend-owned errors pass through as upstream responses.

## Runtime Configuration

- `GATEWAY_LISTEN_ADDR`
- `GATEWAY_UPSTREAM_BASE_URL`
- `GATEWAY_REQUEST_TIMEOUT`
- `GATEWAY_LOG_LEVEL`
- `GATEWAY_ENABLE_METRICS`
- `GATEWAY_OTEL_ENABLED`
- `GATEWAY_OTEL_SERVICE_NAME`
- `GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT`
- `GATEWAY_ALLOW_EXTRACT`
- `GATEWAY_ALLOW_EXTRACT_JOBS`
- `GATEWAY_ALLOW_JOB_STATUS`
- `GATEWAY_MAX_BODY_BYTES`
- `GATEWAY_CONCURRENCY_LIMIT`
- `GATEWAY_RATE_LIMIT_PER_SECOND`
- `GATEWAY_RATE_LIMIT_BURST`
