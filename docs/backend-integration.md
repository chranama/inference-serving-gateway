# Backend Integration

The gateway is designed to run with `llm-extraction-platform`, while remaining
testable with a mock upstream.

## Integration Boundary

The gateway forwards extraction routes to the backend:

- `POST /v1/extract`
- `POST /v1/extract/jobs`
- `GET /v1/extract/jobs/{job_id}`
- `GET /readyz`

The backend remains responsible for authentication, schemas, model execution,
validation, repair, async job state, and backend-side trace details.

The gateway adds service-boundary behavior:

- request and trace identity propagation
- OpenTelemetry propagation
- gateway access logs and metrics
- route policy
- timeout and admission controls
- edge-owned structured errors

## Backend Prerequisites

For local backend integration, start `llm-extraction-platform` first and provide:

- `LLM_EXTRACTION_PLATFORM_BASE_URL`
- `LLM_EXTRACTION_PLATFORM_API_KEY`

For the richer observability artifact bundle, also provide:

- `LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY`

The backend must trust gateway-provided identity headers when running behind the
gateway. In the local integration harness this is represented by backend
`EDGE_MODE=behind_gateway`.

## Canonical Joint Workflow

The canonical LLMEP plus gateway workflow is owned by the backend repository:

- [LLMEP: Inference Gateway Integration](https://github.com/chranama/llm-extraction-platform/blob/main/docs/inference-gateway-integration.md)

That workflow starts LLMEP, the async worker, local infrastructure, optional
observability services, and this gateway as one stack. It also writes the joint
proof artifact bundle from the backend side.

## Gateway-Side Helpers

The gateway runbook keeps helper paths for isolated gateway review and for
probing an already running backend:

- [Runbook: Backend Integration](runbook.md#backend-integration-stack)

Use those helpers when reviewing gateway behavior in isolation or when LLMEP is
already running. Use the LLMEP canonical workflow when presenting the combined
system.

## Inspectable Outputs

The gateway-side backend integration scripts write artifacts under:

- `proof/artifacts/llm_extraction_platform/observability_latest/`
- `proof/artifacts/kind_stack/observability_latest/`

Representative files:

- `gateway.metrics.txt`
- `backend.metrics.txt`
- `sync_trace_detail.json`
- `async_trace_detail.json`
- `sync_otel_trace.json`
- `async_otel_trace.json`
- `sync_logs.json`
- `async_logs.json`
- `manifest.json`
- `summary.md`

These artifacts show request identity, trace identity, gateway/backend metrics,
and sync plus async execution visibility from one run.

## Current Limit

The live backend path depends on a separately runnable
`llm-extraction-platform` checkout. The default gateway test suite and mock
artifacts do not require that backend.
