# Runbook

This guide covers local startup, verification, observation, and shutdown. The
promoted combined workflow is the live `kind` deployment with
`llm-extraction-platform`, this gateway, and a CPU-only `llama.cpp` model
server. The proof workflows remain available when generated evidence is needed.

## Requirements

- Go
- Python 3 for the mock upstream
- Optional: Docker and Docker Compose for the mock Compose stack
- Optional: `kind`, `kubectl`, and Docker for the Kubernetes-shaped local stack
- Optional: sibling `llm-extraction-platform` checkout and a local GGUF model
  file for the joint live kind workflow

## Promoted Joint Kind Workflow

Use these targets when presenting the combined LLMEP plus gateway system:

```bash
make joint-kind-up
make joint-kind-status
make joint-kind-smoke
make joint-kind-down
```

`joint-kind-smoke` verifies the running stack without writing proof artifacts.
It checks gateway and backend readiness, llama-server health, sync extraction,
and async extraction through the gateway.

This workflow uses the sibling LLMEP checkout, reads the backend `.env.docker`
model settings by default, mounts `LLAMA_MODELS_DIR` into the kind control-plane
node at `/models`, and applies LLMEP API/worker, llama-server, gateway, OTel,
and Jaeger resources. If the `llm` kind cluster already exists without that
mount, delete and recreate it before running the live workflow.

Set `PHASE2_KIND_ENV_FILE=/path/to/env` to use a different model env file.
Set `PHASE2_KIND_CLUSTER=llm-live` to run the live workflow in a separate
cluster instead of recreating an existing `llm` cluster that lacks the `/models`
mount.

The harness preloads third-party runtime images into kind by default. Set
`PHASE2_KIND_PRELOAD_IMAGES=0` only when Kubernetes should pull them from inside
the cluster.

## Make Targets

Common targets:

```bash
make test
make joint-kind-up
make joint-kind-status
make joint-kind-smoke
make joint-kind-down
```

Evidence and isolated gateway targets:

```bash
make proof
make proof-host
make proof-compose
make proof-otel
make proof-kind-up
make proof-kind-status
make proof-kind
make proof-kind-down
make joint-kind-proof
```

`make proof` runs the broad Docker Compose mock proof. `make proof-isolated`
runs host-process, Docker Compose, and isolated OpenTelemetry proofs. The kind
mock workflow is split into explicit up, proof, status, and down targets
because it creates or reuses a local cluster. `make joint-kind-proof` generates
the artifact bundle for the promoted live kind path.

The proof scripts check required localhost ports before starting. Override ports
with `GATEWAY_PORT`, `UPSTREAM_PORT`, `JAEGER_PORT`,
`COLLECTOR_HEALTH_PORT`, or `MOCK_KIND_GATEWAY_LOCAL_PORT` when the default
ports are occupied.

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
make proof-host
```

The script starts the mock upstream and gateway, captures representative
responses, writes artifacts under `proof/artifacts/mock_upstream/latest/`, and
shuts down the local processes.

## Generate Docker Compose Mock Artifacts

Run:

```bash
make proof-compose
```

The script starts the Docker Compose mock stack across several runtime
configurations. It captures Compose service state, runtime config, container
logs, health, readiness, metrics, forwarding behavior, unsupported routes,
route toggles, metrics-disabled behavior, and gateway-owned rejection paths. It
writes artifacts under `proof/artifacts/mock_compose/latest/` and shuts down the
Compose stack unless `KEEP_STACK=1` is set.

## Generate Isolated OTel Artifacts

Run:

```bash
make proof-otel
```

The script starts a Docker Compose stack with the gateway, mock upstream,
OpenTelemetry Collector, and Jaeger. It sends a sync extraction request, verifies
trace context reaches the mock upstream, queries Jaeger for the exported gateway
trace, writes artifacts under `proof/artifacts/mock_compose_otel/latest/`, and
shuts down the Compose stack unless `KEEP_STACK=1` is set.

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

For the isolated OTel stack, use:

```bash
docker compose -f deployments/docker-compose.mock.otel.yml up --build
docker compose -f deployments/docker-compose.mock.otel.yml down
```

Host endpoints:

- Gateway: `http://127.0.0.1:18086`
- Mock upstream: `http://127.0.0.1:18087`
- Collector health: `http://127.0.0.1:13134`
- Jaeger UI: `http://127.0.0.1:16687`

## Isolated Kind Mock Stack

Start the gateway plus mock upstream in a local `kind` cluster:

```bash
make proof-kind-up
```

Inspect:

```bash
make proof-kind-status
```

Generate proof artifacts:

```bash
make proof-kind
```

Stop the Kubernetes resources:

```bash
make proof-kind-down
```

Artifacts are written under `proof/artifacts/mock_kind/latest/`. The cluster is
left intact so repeated runs do not recreate it.

## Backend Integration Stack

Use these paths only when the companion `llm-extraction-platform` checkout and
local infrastructure requirements are available.

For the canonical combined LLMEP plus gateway workflow, use the backend-owned
runbook:

- [LLMEP: Inference Gateway Integration](https://github.com/chranama/llm-extraction-platform/blob/main/docs/inference-gateway-integration.md)

The commands below remain useful as gateway-side helpers when the backend is
already running or when you need to inspect this repository's local stack
scripts directly.

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

For the primary local Kubernetes-shaped stack with the companion backend and a
live CPU-only `llama.cpp` model server:

```bash
make joint-kind-up
make joint-kind-status
make joint-kind-smoke
make joint-kind-down
```

To generate the evidence bundle for the same stack, run:

```bash
make joint-kind-proof
```

To run the older deterministic fake-backend kind smoke variant instead:

```bash
PHASE2_KIND_WORKFLOW=fake proof/run_kind_stack.sh up
PHASE2_KIND_WORKFLOW=fake proof/run_kind_stack.sh proof
PHASE2_KIND_WORKFLOW=fake proof/run_kind_stack.sh down
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
