# Runbook

This guide covers local startup, verification, observation, and shutdown.

## Requirements

- Go
- Python 3 for the mock upstream
- Optional: Docker and Docker Compose for the mock Compose stack
- Optional: `kind`, `kubectl`, and Docker for the Kubernetes-shaped local stack

## Run With Mock Upstream

Start the mock upstream:

```bash
python3 proof/mock_upstream.py --port 18081
```

In another shell, start the gateway:

```bash
GATEWAY_UPSTREAM_BASE_URL=http://127.0.0.1:18081 go run ./cmd/gateway
```

Verify the gateway:

```bash
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:8080/readyz
curl -fsS http://127.0.0.1:8080/metrics
```

Stop both processes with `Ctrl-C`.

## Generate Mock Artifacts

Run:

```bash
proof/generate_mock_proof.sh
```

The script starts the mock upstream and gateway, captures representative
responses, writes artifacts under `proof/artifacts/mock_upstream/latest/`, and
shuts down the local processes.

## Docker Compose Mock Stack

Start:

```bash
docker compose -f deployments/docker-compose.mock.yml up --build
```

Inspect:

```bash
curl -fsS http://127.0.0.1:18080/healthz
curl -fsS http://127.0.0.1:18080/readyz
curl -fsS http://127.0.0.1:18080/metrics
```

Stop:

```bash
docker compose -f deployments/docker-compose.mock.yml down
```

## Backend Integration Stack

Use these paths only when the companion `llm-extraction-platform` checkout and
local infrastructure requirements are available.

Run the basic live-backend integration probe against an already running backend:

```bash
LLM_EXTRACTION_PLATFORM_BASE_URL=http://127.0.0.1:8000 \
LLM_EXTRACTION_PLATFORM_API_KEY=... \
proof/run_llm_extraction_platform_integration.sh
```

Generate the integrated observability artifact bundle against an already running
backend:

```bash
LLM_EXTRACTION_PLATFORM_BASE_URL=http://127.0.0.1:8000 \
LLM_EXTRACTION_PLATFORM_API_KEY=... \
LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY=... \
proof/generate_llm_extraction_platform_observability_pack.sh
```

For a local gateway plus backend stack:

```bash
proof/run_local_stack.sh up
proof/run_local_stack.sh status
proof/run_local_stack.sh proof
proof/run_local_stack.sh down
```

For a local Kubernetes-shaped stack:

```bash
proof/run_kind_stack.sh up
proof/run_kind_stack.sh status
proof/run_kind_stack.sh proof
proof/run_kind_stack.sh down
```

## Common Checks

If `/readyz` fails, inspect whether the upstream backend or mock upstream is
running and reachable from `GATEWAY_UPSTREAM_BASE_URL`.

If forwarding fails, check:

- `GATEWAY_UPSTREAM_BASE_URL`
- `GATEWAY_REQUEST_TIMEOUT`
- route toggles such as `GATEWAY_ALLOW_EXTRACT`
- request size relative to `GATEWAY_MAX_BODY_BYTES`
- concurrency and rate-limit settings

If trace identity is missing, check the request headers and whether the backend
is running in a mode that trusts gateway-provided identity headers.
