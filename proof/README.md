# Proof Helpers

This directory contains proof helpers for the gateway in two modes:

- mock-upstream proof
- real backend integration proof
- integrated observability proof

## Mock Upstream Proof

This is the canonical proof path for `inference-serving-gateway v1`.

Command:

```bash
proof/generate_mock_proof.sh
```

What it does:

- starts the local Python mock upstream
- starts the Go gateway
- captures:
  - `healthz`
  - `readyz`
  - `metrics`
  - sync extract forwarding
  - async submit forwarding
  - async status polling

Artifacts are written under:

- `proof/artifacts/mock_upstream/latest/`

Key proof files:

- `manifest.json`
- `summary.md`
- `extract.headers`
- `extract.body.json`
- `extract_jobs.headers`
- `extract_jobs.body.json`
- `job_status.headers`
- `job_status.body.json`

What this path proves:

- stable route surface for sync and async extract
- gateway-owned request and trace identity behavior
- readiness and metrics surfaces
- a reproducible local demo path independent of the real backend

## `llm-extraction-platform` Integration Probe

Command:

```bash
LLM_EXTRACTION_PLATFORM_BASE_URL=http://127.0.0.1:8000 proof/run_llm_extraction_platform_integration.sh
```

Use this only when the real backend is already running and configured.

This path is intentionally treated as:

- backend `v3` integration proof

not:

- the release gate for gateway `v1`

## Integrated Observability Pack

Command:

```bash
LLM_EXTRACTION_PLATFORM_BASE_URL=http://127.0.0.1:8000 \
LLM_EXTRACTION_PLATFORM_API_KEY=... \
LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY=... \
proof/generate_llm_extraction_platform_observability_pack.sh
```

Use this when you want the Phase 1 end-to-end observability artifact bundle rather than only a routing probe.

Backend prerequisite:

- start `llm-extraction-platform` with `EDGE_MODE=behind_gateway`
- otherwise the backend will not trust gateway-provided trace headers and the shared trace contract will fail
- for the canonical local proof environment, use:
  - `MODELS_YAML=/Users/chranama/career/llm-extraction-platform/proof/fixtures/models.observability-proof.yaml`
  - `MODELS_PROFILE=observability-proof`
  - `SCHEMAS_DIR=/Users/chranama/career/llm-extraction-platform/schemas/model_output`

Canonical backend/worker contract for this proof:

```bash
APP_ROOT=/Users/chranama/career/llm-extraction-platform
APP_PROFILE=test
MODELS_PROFILE=observability-proof
MODELS_YAML=/Users/chranama/career/llm-extraction-platform/proof/fixtures/models.observability-proof.yaml
SCHEMAS_DIR=/Users/chranama/career/llm-extraction-platform/schemas/model_output
DATABASE_URL=postgresql+asyncpg://llm:llm@127.0.0.1:5433/llm
REDIS_ENABLED=1
REDIS_URL=redis://127.0.0.1:6379/0
EDGE_MODE=behind_gateway
```

This path captures:

- gateway request logs
- gateway metrics
- backend metrics
- backend admin trace detail for sync and async flows
- backend admin execution-log slices for sync and async execution IDs
- a generated manifest and summary

Artifacts are written under:

- `proof/artifacts/llm_extraction_platform/observability_latest/`

This path is the canonical Phase 1 proof for:

- shared request and trace identity
- gateway/backend correlation
- sync plus async observability

Semantics note:

- `/v1/admin/logs` is treated as an inference-execution surface
- async poll requests are expected to show up in request logs and trace events
- `async_poll_logs.json` may therefore be empty without indicating a proof failure

Phase 2 local-environment contract:

- `/Users/chranama/career/inference-serving-gateway/docs/local-environment-contract.md`

## Phase 2 Local Stack Harness

Canonical entrypoint:

```bash
proof/run_local_stack.sh up
```

Helpful subcommands:

```bash
proof/run_local_stack.sh status
proof/run_local_stack.sh proof
proof/run_local_stack.sh down
```

This harness reuses the backend repository's host-published infra and observability compose profiles, then starts the backend, worker, and gateway on the host with the canonical Phase 2 contract.

When `PHASE2_WITH_OTEL=1` (the default), the local stack also brings up:

- OpenTelemetry Collector on `http://127.0.0.1:4318/v1/traces`
- Jaeger on `http://127.0.0.1:16686`

The host-run gateway, backend, and worker export OTLP/HTTP traces into that collector by default.

## Phase 2 Kind Stack Harness

Canonical entrypoint:

```bash
proof/run_kind_stack.sh up
```

Helpful subcommands:

```bash
proof/run_kind_stack.sh status
proof/run_kind_stack.sh proof
proof/run_kind_stack.sh down
```

This harness is the Kubernetes-shaped companion to the Compose-backed local stack:

- the local stack harness uses Docker Compose for infra and host-run app processes
- the kind harness builds local images, loads them into `kind`, applies the backend observability overlay, and deploys gateway + worker add-ons in-cluster

Kind contract docs:

- `/Users/chranama/career/inference-serving-gateway/docs/kind-deployment-contract.md`
- `/Users/chranama/career/llm-extraction-platform/docs/kind-deployment-contract.md`
