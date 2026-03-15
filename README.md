# inference-serving-gateway

Go service intended to front inference backends with production-style serving/runtime controls:

- request admission
- timeout and cancellation handling
- concurrency and rate controls
- request and trace propagation
- edge metrics and structured logs
- readiness checks against upstream inference services

## Status

Scaffold only. This repository is being created in isolation before `llm-extraction-platform` adds explicit gateway-aware support in a future `v3.0.0` release.

Current plan:
1. build the gateway against a mock upstream
2. validate sync and async forwarding behavior
3. integrate with `llm-extraction-platform`
4. add a canonical proof stack showing end-to-end trace continuity

## Intended Upstream

Initial target upstream:
- `llm-extraction-platform`

Canonical boundary spec:
- [`../llm-extraction-platform/docs/service-boundary.inference-serving-gateway.md`](../llm-extraction-platform/docs/service-boundary.inference-serving-gateway.md)

## Planned Scope

Initial v1 focus:
- `POST /v1/extract`
- `POST /v1/extract/jobs`
- `GET /v1/extract/jobs/{job_id}`
- `GET /healthz`
- `GET /readyz`
- `GET /metrics`

## Repository Layout

```text
cmd/gateway/              main entrypoint
internal/config/          configuration parsing and validation
internal/httpapi/         route wiring and handlers
internal/middleware/      request ID, limits, timeouts, logging
internal/policy/          route/model allowlists and edge checks
internal/upstream/        upstream HTTP client and proxy behavior
internal/observability/   metrics, tracing, structured logs
internal/health/          health and readiness checks
internal/limiter/         concurrency and rate limiting
internal/errors/          structured edge error contracts
docs/                     architecture and design notes
deployments/              compose/k8s manifests later
proof/                    proof artifacts and scripts later
tests/                    integration and end-to-end tests
```

## Near-Term Deliverables

- Go module and HTTP server bootstrap
- mock upstream integration tests
- request ID propagation
- timeout budgets
- structured error responses
- Prometheus metrics
- readiness checks
