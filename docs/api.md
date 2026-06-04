# API

The gateway exposes extraction, health, readiness, and metrics endpoints. It
forwards accepted extraction requests to the configured upstream backend.

An inference gateway sits between a client and a model-serving backend. It does
not run the model itself; it controls which requests are admitted, forwards
accepted requests, and preserves request identity so behavior can be traced
across services.

## OpenAPI

The static OpenAPI contract lives at:

- [openapi.yaml](openapi.yaml)

The Go service does not currently host a Swagger UI. The OpenAPI file can be
opened in Swagger Editor or another OpenAPI viewer when an interactive contract
view is useful.

## Gateway Boundary

Successful extraction responses are backend-owned and forwarded by the gateway.
The gateway does not parse extraction schemas, execute models, validate model
outputs, or manage async job state.

Gateway-owned behavior includes:

- request and trace identity headers
- route allowlist decisions
- request-size, rate, concurrency, and timeout admission
- readiness checks against the upstream backend
- Prometheus metrics
- OpenTelemetry propagation
- structured edge errors

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

| Header | Direction | Behavior |
|---|---|---|
| `X-Request-ID` | request and response | Client request id. Assigned by the gateway when missing. |
| `X-Trace-ID` | request and response | Application trace id. Assigned by the gateway when missing. |
| `X-Gateway-Proxy` | upstream request | Set to `inference-serving-gateway` for forwarded requests. |

Backend auth or API-key headers are forwarded when supplied by the client.

## Health And Readiness

### `GET /healthz`

`/healthz` checks whether the gateway process is live. It does not call the
upstream backend.

Example response:

```json
{
  "status": "ok"
}
```

### `GET /readyz`

`/readyz` calls upstream `/readyz`. It returns ready only when the backend is
reachable and responds with a 2xx status.

Example response:

```json
{
  "status": "ready"
}
```

If the upstream readiness check fails, the gateway returns `upstream_unavailable`.

## Synchronous Extraction

### `POST /v1/extract`

The gateway forwards the request body to upstream `/v1/extract` without
interpreting the extraction payload.

The mock proof run uses this request body:

```json
{
  "schema_id": "demo_schema_v1",
  "text": "Vendor: ACME\nTotal: 10.00"
}
```

Example request:

```bash
curl -fsS -X POST "http://127.0.0.1:18080/v1/extract" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: proof-request-1" \
  -H "X-Trace-ID: proof-trace-1" \
  --data '{
    "schema_id": "demo_schema_v1",
    "text": "Vendor: ACME\nTotal: 10.00"
  }'
```

Example mock response:

```json
{
  "path": "/v1/extract",
  "method": "POST",
  "body": "{\"schema_id\":\"demo_schema_v1\",\"text\":\"Vendor: ACME\\nTotal: 10.00\"}",
  "request_id": "proof-request-1",
  "trace_id": "proof-trace-1"
}
```

Real backend response fields depend on the configured upstream service. The
gateway preserves the response status and non-hop-by-hop response headers, then
sets `X-Request-ID` and `X-Trace-ID` on the client response.

## Asynchronous Extraction

### `POST /v1/extract/jobs`

The gateway forwards the request body to upstream `/v1/extract/jobs` and returns
the upstream job-submission response.

Example request:

```bash
curl -fsS -X POST "http://127.0.0.1:18080/v1/extract/jobs" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: proof-request-2" \
  -H "X-Trace-ID: proof-trace-2" \
  --data '{
    "schema_id": "demo_schema_v1",
    "text": "Vendor: ACME\nTotal: 10.00"
  }'
```

Example mock response:

```json
{
  "job_id": "job-123",
  "status": "queued",
  "request_id": "proof-request-2",
  "trace_id": "proof-trace-2"
}
```

### `GET /v1/extract/jobs/{job_id}`

The gateway forwards job-status polling to upstream
`/v1/extract/jobs/{job_id}`. Async job state is backend-owned.

Example request:

```bash
curl -fsS "http://127.0.0.1:18080/v1/extract/jobs/job-123" \
  -H "X-Request-ID: proof-request-3" \
  -H "X-Trace-ID: proof-trace-2"
```

Example mock response:

```json
{
  "job_id": "job-123",
  "status": "succeeded",
  "trace_id": "proof-trace-2",
  "request_id": "proof-request-3"
}
```

The polling request has its own request id while preserving the async workflow's
trace id.

## Edge-Owned Errors

The gateway returns structured JSON errors for failures it owns.

Example:

```json
{
  "error": {
    "code": "request_too_large",
    "message": "request body exceeds gateway limit",
    "request_id": "proof-request-1"
  }
}
```

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

## OpenTelemetry

When OpenTelemetry is enabled, the gateway creates server spans for incoming
requests and client spans for upstream calls. It injects W3C trace context into
the forwarded upstream request.

Configuration:

- `GATEWAY_OTEL_ENABLED`
- `GATEWAY_OTEL_SERVICE_NAME`
- `GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT`

## Runtime Configuration

| Variable | Purpose |
|---|---|
| `GATEWAY_LISTEN_ADDR` | Gateway listen address. Defaults to `:8080`. |
| `GATEWAY_UPSTREAM_BASE_URL` | Required absolute URL for the upstream backend. |
| `GATEWAY_REQUEST_TIMEOUT` | Timeout budget for upstream-facing routes. |
| `GATEWAY_LOG_LEVEL` | Structured log level. |
| `GATEWAY_ENABLE_METRICS` | Enables `/metrics`. |
| `GATEWAY_OTEL_ENABLED` | Enables OpenTelemetry tracing. |
| `GATEWAY_OTEL_SERVICE_NAME` | Service name used in traces. |
| `GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP exporter endpoint. |
| `GATEWAY_ALLOW_EXTRACT` | Enables or disables `POST /v1/extract`. |
| `GATEWAY_ALLOW_EXTRACT_JOBS` | Enables or disables `POST /v1/extract/jobs`. |
| `GATEWAY_ALLOW_JOB_STATUS` | Enables or disables `GET /v1/extract/jobs/{job_id}`. |
| `GATEWAY_MAX_BODY_BYTES` | Maximum accepted request body size. |
| `GATEWAY_CONCURRENCY_LIMIT` | Concurrent request admission limit. |
| `GATEWAY_RATE_LIMIT_PER_SECOND` | Token refill rate for request rate limiting. |
| `GATEWAY_RATE_LIMIT_BURST` | Rate-limit burst size. |
