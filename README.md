# inference-serving-gateway

Go HTTP gateway for routing extraction requests to an inference backend.

The gateway owns edge behavior around request admission, timeouts, route policy,
request and trace identity, structured edge errors, readiness, metrics, and
OpenTelemetry propagation. The upstream backend still owns model execution,
extraction semantics, schema validation, and async job state.

An inference gateway sits between clients and a model-serving backend. It does
not run the model itself; it controls which requests are admitted, forwards
accepted requests, and preserves request identity so behavior can be traced
across services.

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

## Run Locally

The local runbook provides the step-by-step guide for starting, verifying,
observing, and shutting down the gateway:

- [Runbook](docs/runbook.md)

It covers the promoted live kind path, mock upstream startup, gateway startup,
health checks, Docker Compose proof, isolated OpenTelemetry proof, isolated
Kubernetes proof, gateway-side backend integration helpers, and cleanup. The
canonical combined LLMEP plus gateway workflow lives in the backend repository:

- [LLMEP Inference Gateway Integration](https://github.com/chranama/llm-extraction-platform/blob/main/docs/inference-gateway-integration.md)
- [LLMEP Runtime Setup](https://github.com/chranama/llm-extraction-platform/blob/main/docs/runtime-setup.md)

## Documentation

- [Architecture](docs/architecture.md)
- [API](docs/api.md)
- [OpenAPI](docs/openapi.yaml)
- [Backend Integration](docs/backend-integration.md)
- [Testing](docs/testing.md)
- [Runbook](docs/runbook.md)
- [Artifacts](docs/artifacts.md)
- [Scope](docs/scope.md)

Older planning and rollout notes have been archived under [`archive/docs/`](archive/docs/).

## Current Scope

This repository shows a local, inspectable gateway service for inference-backed
extraction workflows. It includes a bounded route surface, explicit runtime
controls, tests for success and failure behavior, and saved artifacts for host,
Compose, isolated OpenTelemetry, isolated Kubernetes, and backend-integrated
runs.

It does not claim full edge authentication, multi-tenant routing, production
autoscaling, high availability, or ownership of backend inference semantics.
