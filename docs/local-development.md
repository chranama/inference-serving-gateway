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

Run the gateway against the local mock upstream:

```bash
python3 proof/mock_upstream.py --port 18081
GATEWAY_UPSTREAM_BASE_URL=http://127.0.0.1:18081 go run ./cmd/gateway
```

Then hit:

- `http://127.0.0.1:8080/healthz`
- `http://127.0.0.1:8080/readyz`
- `http://127.0.0.1:8080/metrics`

## Docker Compose

Build and run the local stack:

```bash
docker compose -f deployments/docker-compose.mock.yml up --build
```

Ports:

- gateway: `http://127.0.0.1:18080`
- mock upstream: `http://127.0.0.1:18081`

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

