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
