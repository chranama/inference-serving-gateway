# Architecture

`inference-serving-gateway` is an edge service in front of inference backends.
It accepts a small extraction-focused API surface, applies gateway-owned runtime
controls, and forwards accepted requests to an upstream backend.

## Request Flow

```text
Client
  -> gateway route
  -> request identity middleware
  -> tracing middleware
  -> access logging and metrics
  -> route policy
  -> rate and concurrency admission
  -> timeout budget
  -> upstream client
  -> inference backend
```

The gateway returns upstream responses when forwarding succeeds. For edge-owned
failures, it returns structured error responses before the request reaches the
backend.

## Gateway Responsibilities

- route `/v1/extract`, `/v1/extract/jobs`, and `/v1/extract/jobs/{job_id}`
- expose health, readiness, and metrics endpoints
- assign or preserve `X-Request-ID`
- assign or preserve `X-Trace-ID`
- inject OpenTelemetry trace context into upstream calls
- enforce route allowlist settings
- enforce request-size, concurrency, rate, and timeout limits
- record gateway and upstream request metrics
- return structured edge errors

## Backend Responsibilities

The upstream backend owns:

- model execution
- extraction semantics
- schema validation and repair
- API-key validation
- async job execution and durable job state
- backend trace detail and execution logs

The gateway intentionally does not parse or reinterpret extraction payloads
beyond request-size admission.

## Main Packages

- `internal/httpapi/`: HTTP routes, handlers, middleware chain, and response handling.
- `internal/upstream/`: backend forwarding and upstream transport errors.
- `internal/middleware/`: request identity, tracing, access logs, policy, timeouts, and limits.
- `internal/config/`: environment configuration and validation.
- `internal/observability/`: metrics, logger construction, and OpenTelemetry setup.
- `internal/policy/`: route-level allowlist.
- `internal/health/`: readiness check against the upstream backend.

## Design Tradeoffs

The gateway is deliberately narrow. It focuses on service-boundary behavior
rather than backend business logic. This keeps the gateway useful with a mock
upstream, while still allowing integration with `llm-extraction-platform`.

The route surface is small so the tests can cover both normal forwarding and
edge-owned failure behavior without requiring a large backend fixture.
