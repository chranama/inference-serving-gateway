# Artifacts

The repository keeps saved runtime artifacts for mock and backend-integrated
runs. They are useful for inspecting behavior without rerunning every local
stack.

## What To Inspect First

- `summary.md`: human-readable run summary and validated expectations.
- `manifest.json`: machine-readable checks and artifact inventory.
- `extract.body.json`: synchronous forwarding and identity propagation.
- `extract_jobs.body.json`: async submission forwarding and identity propagation.
- `job_status.body.json`: async polling and trace continuity.
- Metrics files: gateway and upstream visibility for the captured run.
- Trace and log files: cross-service correlation when the backend integration
  stack is available.

## Mock Upstream Artifacts

Generate these artifacts through the runbook's mock artifact workflow.

Output directory:

```text
proof/artifacts/mock_upstream/latest/
```

Representative files:

- `manifest.json`
- `summary.md`
- `healthz.body.json`
- `readyz.body.json`
- `metrics.txt`
- `extract.headers`
- `extract.body.json`
- `extract_jobs.headers`
- `extract_jobs.body.json`
- `job_status.headers`
- `job_status.body.json`
- `gateway.log`
- `mock-upstream.log`

These artifacts show that the gateway can serve health, readiness, metrics,
sync extraction forwarding, async job submission, and async status polling
against a local mock backend.

## Backend Integration Artifacts

Generate these artifacts through the runbook's local backend or `kind` workflow.

Output directories:

```text
proof/artifacts/llm_extraction_platform/observability_latest/
proof/artifacts/kind_stack/observability_latest/
```

Representative files:

- `manifest.json`
- `summary.md`
- `gateway.metrics.txt`
- `backend.metrics.txt`
- `sync_trace_detail.json`
- `async_trace_detail.json`
- `sync_otel_trace.json`
- `async_otel_trace.json`
- `sync_logs.json`
- `async_logs.json`
- `async_poll_logs.json`

These artifacts show gateway/backend correlation for sync and async extraction
flows when the companion backend stack is available.

## Interpretation Limits

Artifacts are bounded local outputs. They show representative behavior and
runtime wiring, not production load, high availability, or long-running
operational stability.
