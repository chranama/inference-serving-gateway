# inference-serving-gateway

Go HTTP gateway for routing extraction requests to an inference backend.

The gateway owns edge behavior around request admission, timeouts, route policy,
request and trace identity, structured edge errors, readiness, metrics, and
OpenTelemetry propagation. The upstream backend still owns model execution,
extraction semantics, schema validation, and async job state.

## What It Does

- Serves `POST /v1/extract` for synchronous extraction forwarding.
- Serves `POST /v1/extract/jobs` for asynchronous extraction submission.
- Serves `GET /v1/extract/jobs/{job_id}` for asynchronous job status polling.
- Exposes `GET /healthz`, `GET /readyz`, and `GET /metrics`.
- Preserves or assigns request and trace identifiers across gateway and backend responses.
- Applies route toggles, request-size limits, concurrency limits, rate limits, and timeout budgets.

## System Boundaries

- `cmd/gateway/`: process entrypoint, config load, tracing setup, and graceful shutdown.
- `internal/httpapi/`: route graph, handlers, middleware composition, and edge error responses.
- `internal/upstream/`: backend HTTP forwarding and upstream request metrics.
- `internal/middleware/`: request identity, access logging, tracing, route policy, limits, and timeouts.
- `internal/config/`: environment-based runtime configuration and validation.
- `internal/policy/`: route-level allowlist decisions.
- `internal/observability/`: Prometheus metrics, structured logging, and OpenTelemetry setup.
- `internal/health/`: upstream readiness checks.
- `tests/`: gateway integration tests with mock upstream behavior.
- `proof/`: local scripts and saved runtime artifacts.

## Commands

Run tests:

```bash
go test ./...
```

Run the gateway against the bundled mock upstream:

```bash
python3 proof/mock_upstream.py --port 18081
GATEWAY_UPSTREAM_BASE_URL=http://127.0.0.1:18081 go run ./cmd/gateway
```

Generate local mock-upstream artifacts:

```bash
proof/generate_mock_proof.sh
```

Run the mock Compose stack:

```bash
docker compose -f deployments/docker-compose.mock.yml up --build
```

## Documentation

- [Architecture](docs/architecture.md)
- [API](docs/api.md)
- [Backend Integration](docs/backend-integration.md)
- [Testing](docs/testing.md)
- [Runbook](docs/runbook.md)
- [Artifacts](docs/artifacts.md)
- [Scope](docs/scope.md)

Older planning and rollout notes have been archived under [`archive/docs/`](archive/docs/).

## Current Scope

This repository shows a local, inspectable gateway service for inference-backed
extraction workflows. It includes a bounded route surface, explicit runtime
controls, tests for success and failure behavior, and saved artifacts for mock
and backend-integrated runs.

It does not claim full edge authentication, multi-tenant routing, production
autoscaling, high availability, or ownership of backend inference semantics.
