# OpenTelemetry Walkthrough

This walkthrough explains how to inspect the OpenTelemetry artifacts produced by the integrated proof helpers.

Primary artifact locations:

- local stack: `/Users/chranama/career/inference-serving-gateway/proof/artifacts/llm_extraction_platform/observability_latest/`
- kind stack: `/Users/chranama/career/inference-serving-gateway/proof/artifacts/kind_stack/observability_latest/`

Identity contracts:

- application identity: `/Users/chranama/career/inference-serving-gateway/docs/trace-identity-contract.md`
- OTel bootstrap contract: `/Users/chranama/career/inference-serving-gateway/docs/opentelemetry-contract.md`

## What To Open

Open these in order:

1. `summary.md`
2. `manifest.json`
3. `sync_otel_trace.json`
4. `async_otel_trace.json`
5. `sync_trace_detail.json`
6. `async_trace_detail.json`

## The Two Trace Layers

There are two different trace concepts in this stack:

- application `trace_id`
  - logical operation identity
  - used by logs, admin trace inspection, proof artifacts, and cross-surface correlation
- OTel `TraceId`
  - transport-level distributed trace identity
  - used by Jaeger to show cross-service spans

The span attributes bridge those layers:

- `llm.request_id`
- `llm.trace_id`
- `llm.job_id`

This means:

- Jaeger shows the distributed execution path
- the existing backend trace/event surfaces still show the application semantics

## Sync Trace

Open `sync_otel_trace.json`.

What to verify:

- the exported trace includes `inference-serving-gateway`
- the exported trace includes `llm-extraction-platform`
- span attributes include the shared application `llm.trace_id`

How to read it:

- gateway spans show the edge request and upstream call
- backend spans show request handling and bounded internal work
- `sync_trace_detail.json` is still the better source for domain events like `extract.completed`

## Async Trace

Open `async_otel_trace.json`.

What to verify:

- the exported trace includes `inference-serving-gateway`
- the exported trace includes `llm-extraction-platform`
- the exported trace includes `llm-extraction-platform-worker`
- span attributes include the shared application `llm.trace_id` and `llm.job_id`

How to read it:

- the submit request starts the distributed trace
- the worker continues it later using persisted W3C trace context
- `async_trace_detail.json` still gives the richer job lifecycle semantics

Important limitation:

- poll requests are separate HTTP traces in OTel
- they keep the same application `trace_id` and `job_id`
- they are not folded into `async_otel_trace.json`

That is intentional. It keeps the distributed tracing story accurate instead of fabricating parent/child relationships.

## Local And Kind Viewers

Local stack:

- Jaeger UI: `http://127.0.0.1:16686`

Kind stack:

- `kubectl -n llm port-forward svc/jaeger 16686:16686`

The proof helpers export JSON artifacts so the trace story remains inspectable even without opening the UI.
