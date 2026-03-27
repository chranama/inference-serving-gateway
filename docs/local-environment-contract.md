# Phase 2 Local Environment Contract

This document defines the canonical local-stack contract that Phase 2 should build around.

The goal is to stop relying on one-off shell memory and make the integrated environment reproducible before Docker Compose or a richer launch path is added.

## Purpose

Phase 2 should treat the local environment as one stack with:

- `llm-extraction-platform` backend
- `llm-extraction-platform` async worker
- `inference-serving-gateway`
- local Postgres
- local Redis

This contract defines the minimum assumptions those pieces should share.

## Topology Contract

Canonical local ports:

- backend: `127.0.0.1:8000`
- gateway: `127.0.0.1:18082`
- Postgres: `127.0.0.1:5433`
- Redis: `127.0.0.1:6379`

Canonical flow:

- client -> gateway -> backend
- async submit -> Redis queue -> worker -> Postgres persistence
- gateway and backend metrics are both scrapeable during proof runs

## Identity Contract

This environment inherits the Phase 1.5 identity semantics:

- `request_id` = one concrete HTTP request
- `trace_id` = one logical operation across submit, worker, and poll
- `job_id` = one async job entity

Reference:

- `/Users/chranama/career/inference-serving-gateway/docs/trace-identity-contract.md`

## Backend Environment Contract

Canonical backend and worker environment:

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

Why each matters:

- `APP_PROFILE=test`: lightweight backend/runtime posture
- `MODELS_PROFILE=observability-proof`: selects the canonical fake backend proof profile
- `MODELS_YAML=...models.observability-proof.yaml`: removes dependence on temp files
- `SCHEMAS_DIR=.../schemas/model_output`: makes schema resolution explicit and stable
- `EDGE_MODE=behind_gateway`: required for trusted gateway trace propagation

## Proof Fixture Contract

Canonical proof fixture:

- `/Users/chranama/career/llm-extraction-platform/proof/fixtures/models.observability-proof.yaml`

The fixture is expected to:

- use the fake backend
- support both sync and async extract
- return data that conforms to `sroie_receipt_v1`

Current fake output:

```json
{"company":"ACME","date":"2026-03-25","total":"10.00"}
```

## Schema And Payload Contract

Canonical observability-pack defaults:

- schema: `sroie_receipt_v1`
- text:
  - `Vendor: ACME`
  - `Total: 10.00`

This means the default observability-pack script can be run without extra payload overrides when the canonical proof fixture is in use.

## Auth Contract

Canonical proof keys:

- standard API key: `proof-user-key`
- admin API key: `proof-admin-key`

Phase 2 automation should assume those are seeded before proof generation.

## Artifact Contract

Canonical output location for the integrated observability proof:

- `/Users/chranama/career/inference-serving-gateway/proof/artifacts/llm_extraction_platform/observability_latest/`

Minimum expected outputs:

- `summary.md`
- `manifest.json`
- `gateway.log`
- `gateway.metrics.txt`
- `backend.metrics.txt`
- `sync_trace_detail.json`
- `async_trace_detail.json`
- `sync_logs.json`
- `async_logs.json`
- `async_poll_logs.json`

## Phase 2 Implication

Phase 2 should build launch automation around this contract instead of redefining it.

That means the next integrated local environment should:

- start services with this env contract by default
- avoid temp proof fixtures
- keep schema resolution explicit
- preserve the trace and execution-log semantics already hardened in Phase 1.5
