# Artifacts

The repository keeps saved runtime artifacts for host, Docker Compose, isolated
OpenTelemetry, isolated `kind`, and backend-integrated runs. They are useful
for inspecting behavior without rerunning every local stack.

## What To Inspect First

- `summary.md`: human-readable run summary and validated expectations.
- `manifest.json`: machine-readable checks and artifact inventory.
- `extract.body.json`: synchronous forwarding and identity propagation.
- `extract_jobs.body.json`: async submission forwarding and identity propagation.
- `job_status.body.json`: async polling and trace continuity.
- Metrics files: gateway and upstream visibility for the captured run.
- Trace and log files: cross-service correlation when the backend integration
  stack is available.

## Host Mock Upstream Artifacts

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

## Docker Compose Mock Artifacts

Generate these artifacts through the runbook's Docker Compose proof workflow.

Output directory:

```text
proof/artifacts/mock_compose/latest/
```

Representative files:

- `manifest.json`
- `summary.md`
- phase-level manifests under `base/`, `timeout/`, `rate_limit/`,
  `route_disabled/`, `extract_jobs_disabled/`, `job_status_disabled/`,
  `metrics_disabled/`, `request_too_large/`, and `upstream_unavailable/`
- runtime snapshots under `runtime/`
- container logs for the gateway and mock upstream

These artifacts show that the containerized gateway can reach the containerized
mock upstream, preserve identity, expose metrics, and enforce gateway-owned
timeout, size, route-policy, rate-limit, concurrency, unsupported-route,
metrics-disabled, and upstream-unavailable paths. Phase manifests include the
runtime config used to trigger each behavior.

## Isolated OTel Mock Artifacts

Generate these artifacts through the runbook's isolated OTel proof workflow.

Output directory:

```text
proof/artifacts/mock_compose_otel/latest/
```

Representative files:

- `manifest.json`
- `summary.md`
- `extract.body.json`
- `extract_otel_trace.json`
- `jaeger-services.json`
- runtime logs for the gateway, mock upstream, OpenTelemetry Collector, and
  Jaeger

These artifacts show that the gateway exports OTLP/HTTP spans to a collector,
the collector forwards traces to Jaeger, the sync extract trace contains the
gateway server and upstream client spans, and W3C trace context reaches the mock
upstream request. The manifest includes the OTel runtime config used by the
gateway.

## Isolated Kind Mock Artifacts

Generate these artifacts through the runbook's isolated kind proof workflow.

Output directory:

```text
proof/artifacts/mock_kind/latest/
```

Representative files:

- `manifest.json`
- `summary.md`
- phase-level manifests under `base/` and `timeout/`
- `port-forward-gateway.log`
- Kubernetes runtime snapshots under `runtime/`
- gateway and mock-upstream container logs

These artifacts show that the gateway can run as a Kubernetes deployment,
resolve the mock upstream through cluster DNS, pass readiness, preserve identity,
and enforce representative gateway-owned controls.

## Backend Integration Artifacts

Generate these artifacts through the runbook's local backend or integrated
`kind` workflow.

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
