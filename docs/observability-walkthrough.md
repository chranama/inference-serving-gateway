# Integrated Observability Walkthrough

This walkthrough explains how to inspect the Phase 1 integrated observability proof for:

- `inference-serving-gateway`
- `llm-extraction-platform`

Identity semantics reference:

- `/Users/chranama/career/inference-serving-gateway/docs/trace-identity-contract.md`

## Purpose

The point of the proof is to show that one request can be followed across:

- gateway edge handling
- backend application handling
- async worker execution
- async polling

without losing the application identity semantics that already existed before OpenTelemetry.

## Generate The Artifact Pack

Before running the pack, the backend should be started in trusted gateway mode:

```bash
EDGE_MODE=behind_gateway
```

Without that setting, the backend will fall back to backend-local trace IDs and the Phase 1.5 shared-trace contract will not hold.

Canonical local proof backend contract:

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

That fixture is designed to match the default pack payload:

- schema: `sroie_receipt_v1`
- text: `Vendor: ACME` / `Total: 10.00`

so the pack can be regenerated without one-off temp files or payload overrides.

Then run:

```bash
LLM_EXTRACTION_PLATFORM_BASE_URL=http://127.0.0.1:8000 \
LLM_EXTRACTION_PLATFORM_API_KEY=... \
LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY=... \
proof/generate_llm_extraction_platform_observability_pack.sh
```

Artifacts are written under:

- `/Users/chranama/career/inference-serving-gateway/proof/artifacts/llm_extraction_platform/observability_latest/`

Phase 2 local-environment contract reference:

- `/Users/chranama/career/inference-serving-gateway/docs/local-environment-contract.md`

## What To Open First

Open these in order:

1. `summary.md`
2. `manifest.json`
3. `sync_trace_detail.json`
4. `async_trace_detail.json`
5. `sync_otel_trace.json` when present
6. `async_otel_trace.json` when present
7. `gateway.metrics.txt`
8. `backend.metrics.txt`

If the pack was generated through the Phase 2 local or kind harnesses, the OTel exports should be present.

OTel-specific walkthrough:

- `/Users/chranama/career/inference-serving-gateway/docs/opentelemetry-walkthrough.md`

## Sync Request Inspection

Use the sync identifiers from `summary.md` and `manifest.json`.

What to verify:

- the gateway response headers preserve the sync `request_id` and `trace_id`
- `sync_trace_detail.json` shows backend events like:
  - `extract.accepted`
  - `extract.model_resolved`
  - `extract.validation_completed`
  - `extract.completed`
- `sync_logs.json` shows backend inference-execution evidence joined by the shared sync `trace_id`
- `sync_otel_trace.json` shows the transport-level distributed trace with:
  - gateway span(s)
  - backend span(s)

Interpretation:

- the gateway owns the edge request surface
- the backend owns the application trace detail
- OTel adds the cross-service execution path; it does not replace the application `trace_id`
- `/v1/admin/logs` is being used here as an execution-log surface, not as raw request logging
- the exact meaning of `request_id`, `trace_id`, and `job_id` is defined in the trace identity contract

## Async Request Inspection

Use the async identifiers from `summary.md` and `manifest.json`.

What to verify:

- async submit preserves the shared async `trace_id`
- async poll preserves the same async `trace_id` while using a distinct poll `request_id`
- `async_trace_detail.json` includes:
  - `extract_job.submitted`
  - `extract_job.worker_claimed`
  - `extract_job.execution_started`
  - `extract.completed`
  - `extract_job.completed`
  - `extract_job.status_polled`
- `async_logs.json` shows backend inference-execution evidence for the async worker path, joined by shared async `trace_id` plus `job_id`
- `async_otel_trace.json` shows the distributed trace for:
  - submit request
  - worker continuation
  not poll requests

Interpretation:

- trace identity follows the async job across submit, worker execution, and polling
- request identity changes where it should, while trace identity remains stable
- poll visibility is richer in access logs and trace events than in execution logs
- poll requests are separate HTTP traces in OTel; they are not forced into the worker continuation trace

Surface note:

- `async_logs.json` reflects execution logging for the worker path
- `sync_logs.json` and `async_logs.json` should be read as execution-log slices, not generic request logs
- `async_poll_logs.json` is captured as an observation artifact; an empty result is expected when `/v1/admin/logs` remains execution-focused
- poll requests are expected to be visible primarily in:
  - backend access logs
  - async trace detail
  not in the inference-log-backed admin log surface

## Metrics Inspection

Use:

- `gateway.metrics.txt` for edge/runtime metrics
- `backend.metrics.txt` for application/runtime metrics

What to verify:

- gateway metrics include:
  - `gateway_requests_total`
  - `gateway_upstream_requests_total`
- backend metrics include:
  - `llm_api_request_total`
  - `llm_extraction_requests_total`

Interpretation:

- the gateway and backend expose different but complementary views of the same flow
- the reviewer does not need one giant telemetry system to understand the runtime stack

## The Main Story

This proof is successful if a reviewer can see that:

- the gateway is not just a thin proxy
- the backend still owns application semantics
- the two systems share correlation identity cleanly
- sync and async flows are both inspectable
- the OTel transport trace path complements, rather than replaces, the application trace/event model

That is the core Phase 1 outcome.
