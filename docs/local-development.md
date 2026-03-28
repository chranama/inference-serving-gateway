# Local Development

## Requirements

- Go `1.26+`
- Python 3 for the mock upstream proof helper
- optional: Docker / Docker Compose for the local two-service stack

## Quick Start

Install dependencies and verify the test suite:

```bash
go mod tidy
go test ./...
```

## Canonical v1 Workflow

For `inference-serving-gateway v1`, the primary local workflow is:

```bash
proof/generate_mock_proof.sh
```

This produces the canonical proof artifacts under:

```text
proof/artifacts/mock_upstream/latest/
```

Use this path when validating:

- route coverage
- request and trace identity behavior
- readiness
- metrics

## Canonical Phase 2 Workflow

For the integrated local stack, the canonical entrypoint is:

```bash
proof/run_local_stack.sh up
```

This harness:

- starts host-published Postgres and Redis via the backend repo compose file
- starts host-published Prometheus and Grafana via the backend repo host-observability profile
- starts host-published OpenTelemetry Collector and Jaeger via the backend repo host-OTel profile
- applies backend migrations
- seeds canonical proof API keys
- starts the host-run backend, async worker, and gateway

Canonical local trace endpoints:

- Collector OTLP/HTTP: `http://127.0.0.1:4318/v1/traces`
- Jaeger UI: `http://127.0.0.1:16686`

Optional flags:

- `PHASE2_WITH_OBS=0`: skip Prometheus and Grafana
- `PHASE2_WITH_OTEL=0`: skip Collector and Jaeger

Companion commands:

```bash
proof/run_local_stack.sh status
proof/run_local_stack.sh proof
proof/run_local_stack.sh down
```

The environment contract behind this workflow is documented in:

- `/Users/chranama/career/inference-serving-gateway/docs/local-environment-contract.md`
- `/Users/chranama/career/llm-extraction-platform/docs/local-environment-contract.md`

## Canonical Phase 2 Kind Workflow

For the Kubernetes-shaped local stack, the canonical entrypoint is:

```bash
proof/run_kind_stack.sh up
```

This harness:

- creates or reuses the local `kind` cluster
- builds and loads the backend and gateway images
- applies the backend observability overlay
- deploys the async worker and gateway in-cluster
- seeds canonical proof API keys with a Kubernetes job

Companion commands:

```bash
proof/run_kind_stack.sh status
proof/run_kind_stack.sh proof
proof/run_kind_stack.sh down
```

The kind contract behind this workflow is documented in:

- `/Users/chranama/career/inference-serving-gateway/docs/kind-deployment-contract.md`
- `/Users/chranama/career/llm-extraction-platform/docs/kind-deployment-contract.md`

## Manual Mock-Upstream Workflow

Run the gateway against the local mock upstream manually:

```bash
python3 proof/mock_upstream.py --port 18081
GATEWAY_UPSTREAM_BASE_URL=http://127.0.0.1:18081 go run ./cmd/gateway
```

Then hit:

- `http://127.0.0.1:8080/healthz`
- `http://127.0.0.1:8080/readyz`
- `http://127.0.0.1:8080/metrics`

## Docker Compose

Build and run the local mock stack:

```bash
docker compose -f deployments/docker-compose.mock.yml up --build
```

Ports:

- gateway: `http://127.0.0.1:18080`
- mock upstream: `http://127.0.0.1:18081`

Compose is useful for local parity, but it is secondary to the canonical proof script for gateway `v1`.

## Main Environment Variables

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
