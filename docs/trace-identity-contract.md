# Trace Identity Contract

This document defines the Phase 1.5 identity model for the integrated:

- `inference-serving-gateway`
- `llm-extraction-platform`

Its purpose is to make the observability semantics explicit and stable.

## Why This Exists

The stack exposes multiple telemetry surfaces:

- gateway access logs
- backend access logs
- backend trace events
- backend admin inference logs via `/v1/admin/logs`

Those surfaces are only easy to interpret if the identity fields have clear meanings.

This contract defines those meanings.

## Identity Fields

## `request_id`

Meaning:

- one ID per concrete HTTP request

Examples:

- one sync extract request
- one async submit request
- one async poll request
- one admin request

Properties:

- every poll request gets its own `request_id`
- request IDs may change across submit, worker, and poll boundaries
- request IDs are the best handle for exact HTTP request correlation

Primary uses:

- gateway access logs
- backend access logs
- request-specific troubleshooting

## `trace_id`

Meaning:

- one stable ID for the full logical operation

Examples:

- one sync extract flow
- one async extract flow spanning:
  - submit
  - worker execution
  - status polling

Properties:

- sync flow:
  - `request_id` and `trace_id` may be the same
- async flow:
  - submit, worker, and poll share one `trace_id`
  - poll `request_id` stays distinct

Primary uses:

- cross-service correlation
- trace inspection
- lifecycle reasoning

In trusted gateway mode:

- the gateway injects `X-Trace-ID`
- the backend preserves it
- admin trace inspection should be queryable directly by that same `trace_id`

## `job_id`

Meaning:

- one stable identifier for the async job entity

Properties:

- only exists for async flows
- created at submit time
- stable across worker execution and status polling

Primary uses:

- async lifecycle joins
- queue and worker reasoning
- tying poll behavior to one concrete async job object

## Async Example

For one async extraction flow:

- submit request:
  - `request_id = async-submit-request-1`
  - `trace_id = async-trace-1`
  - `job_id = abc123`

- worker execution:
  - `request_id = async-submit-request-1` or another execution-specific request ID, depending on implementation
  - `trace_id = async-trace-1`
  - `job_id = abc123`

- poll request:
  - `request_id = async-poll-request-1`
  - `trace_id = async-trace-1`
  - `job_id = abc123`

This is the intended pattern:

- request identity can vary
- trace identity stays stable
- job identity stays stable

## Surface Semantics

## Access logs

Meaning:

- all HTTP requests

Expected fields:

- `request_id`
- `trace_id`
- `job_id` where applicable
- method
- route/path
- status_code
- latency

Includes:

- submit requests
- poll requests
- health/metrics requests
- admin requests

Use access logs when the question is:

- "Did this exact HTTP request happen?"

## Trace events

Meaning:

- lifecycle timeline of the logical operation

Expected fields:

- `trace_id`
- `request_id`
- `job_id`
- stage
- status
- route
- model_id where applicable

Includes:

- async queue/persist steps
- worker claim/execution steps
- poll events
- completion/failure steps

Use trace events when the question is:

- "How did this operation progress over time?"

## Inference logs

Meaning:

- persisted records of actual inference execution attempts

Expected fields:

- `request_id`
- `trace_id` once enriched
- `job_id` once enriched
- route
- model_id
- prompt/output
- latency
- token counts
- status/error metadata

Should not include:

- pure status polling
- generic admin reads

Use inference logs when the question is:

- "What execution actually ran, with what inputs, outputs, and latency?"

## Current Poll Visibility Rule

Async poll requests are expected to be visible in:

- gateway access logs
- backend access logs
- backend trace events

They are not required to appear in:

- `/v1/admin/logs`

That distinction is intentional.
Polling is a request-level visibility concern, not an inference execution.

Another way to say it:

- access logs answer: "did this concrete poll request happen?"
- trace events answer: "how did the async operation progress?"
- `/v1/admin/logs` answers: "what inference execution actually ran?"

## Trusted Gateway Mode

The shared trace contract depends on trusted gateway mode.

Required backend behavior:

- `EDGE_MODE=behind_gateway`
- trust `X-Trace-ID` only when:
  - `X-Gateway-Proxy: inference-serving-gateway`
  - is present

If trusted gateway mode is not enabled:

- the backend may fall back to backend-local trace IDs
- the integrated trace contract will not hold

## What A Reviewer Should Infer

From this contract, a reviewer should be able to tell:

- `request_id` is for HTTP request granularity
- `trace_id` is for end-to-end logical operation correlation
- `job_id` is for async job entity correlation
- poll requests are visible, but not misclassified as inference executions

That is the intended observability model for the integrated stack.
