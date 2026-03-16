# inference-serving-gateway

Go service intended to front inference backends with production-style serving/runtime controls:

- request admission
- timeout and cancellation handling
- concurrency and rate controls
- request and trace propagation
- edge metrics and structured logs
- readiness checks against upstream inference services

## Status

Early MVP implemented. This repository now includes:

- a runnable Go HTTP service
- health, readiness, and metrics endpoints
- sync and async forwarding routes
- request and trace propagation
- timeout handling
- coarse route policy toggles
- request-size admission control
- concurrency and rate limiting
- mock-upstream proof scripts
- Go unit and integration tests

Current plan:
1. continue iterating against the mock upstream
2. harden proof artifacts and local deployment story
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

## Quick Start

Install Go dependencies and run the test suite:

```bash
go mod tidy
go test ./...
```

Run the gateway against the bundled mock upstream:

```bash
python3 proof/mock_upstream.py --port 18081
GATEWAY_UPSTREAM_BASE_URL=http://127.0.0.1:18081 go run ./cmd/gateway
```

Main endpoints:

- `GET /healthz`
- `GET /readyz`
- `GET /metrics`
- `POST /v1/extract`
- `POST /v1/extract/jobs`
- `GET /v1/extract/jobs/{job_id}`

Generate local proof artifacts:

```bash
proof/generate_mock_proof.sh
```

Docker Compose local stack:

```bash
docker compose -f deployments/docker-compose.mock.yml up --build
```

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

- refine the mock-upstream proof story
- add stronger documentation and example artifacts
- validate forwarding against `llm-extraction-platform`
- extend proof coverage for trace continuity through the real backend

## Runtime Configuration

- `GATEWAY_LISTEN_ADDR`
- `GATEWAY_UPSTREAM_BASE_URL`
- `GATEWAY_REQUEST_TIMEOUT`
- `GATEWAY_LOG_LEVEL`
- `GATEWAY_ENABLE_METRICS`
- `GATEWAY_ALLOW_EXTRACT`
- `GATEWAY_ALLOW_EXTRACT_JOBS`
- `GATEWAY_ALLOW_JOB_STATUS`
- `GATEWAY_MAX_BODY_BYTES`
- `GATEWAY_CONCURRENCY_LIMIT`
- `GATEWAY_RATE_LIMIT_PER_SECOND`
- `GATEWAY_RATE_LIMIT_BURST`

## Edge-Owned Error Classes

- `invalid_request`
- `unsupported_route`
- `upstream_timeout`
- `upstream_unavailable`
- `request_too_large`
- `route_not_allowed`
- `concurrency_limited`
- `rate_limited`
