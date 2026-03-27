# `llm-extraction-platform` Integration Notes

This repository was intentionally built against a mock upstream first.

The live backend integration target is:

- `llm-extraction-platform v3`

Source-of-truth boundary document:

- `../../llm-extraction-platform/docs/service-boundary.inference-serving-gateway.md`

## What The Gateway Assumes

The gateway treats the backend as an HTTP service that already owns:

- extraction semantics
- async job execution
- trace-detail recording
- validation and repair logic

The gateway only adds:

- edge admission
- request and trace propagation
- timeouts
- forwarding
- edge logs and metrics
- readiness aggregation

Identity semantics reference:

- `/Users/chranama/career/inference-serving-gateway/docs/trace-identity-contract.md`

## Live Integration Proof

Use:

```bash
proof/run_llm_extraction_platform_integration.sh
```

Required environment:

- `LLM_EXTRACTION_PLATFORM_BASE_URL`
- `LLM_EXTRACTION_PLATFORM_API_KEY`

Backend expectations:

- the backend exposes:
  - `POST /v1/extract`
  - `POST /v1/extract/jobs`
  - `GET /v1/extract/jobs/{job_id}`
  - `GET /healthz`
  - `GET /readyz`
- the backend still owns API-key validation for `v3`
- the backend schema set includes `sroie_receipt_v1`

The script is designed to:

- start the gateway against the real backend
- issue sync extract requests through the gateway
- issue async submit and poll requests through the gateway
- wait until the async job reaches a terminal state
- preserve and surface request/trace identifiers in saved artifacts

Primary generated artifacts:

- `extract.body.json`
- `extract.headers`
- `extract_jobs.body.json`
- `extract_jobs.headers`
- `job_status.body.json`
- `job_status.headers`
- `gateway.log`

## Phase 1 Observability Pack

For the richer end-to-end observability artifact bundle, use:

```bash
LLM_EXTRACTION_PLATFORM_BASE_URL=http://127.0.0.1:8000 \
LLM_EXTRACTION_PLATFORM_API_KEY=... \
LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY=... \
proof/generate_llm_extraction_platform_observability_pack.sh
```

Backend prerequisite:

- run the backend with `EDGE_MODE=behind_gateway`
- the gateway already sends `X-Gateway-Proxy`, and the backend must be in trusted gateway mode for shared trace IDs to survive into response headers and admin trace inspection
- for the canonical local proof path, run it with:
  - `MODELS_PROFILE=observability-proof`
  - `MODELS_YAML=/Users/chranama/career/llm-extraction-platform/proof/fixtures/models.observability-proof.yaml`
  - `SCHEMAS_DIR=/Users/chranama/career/llm-extraction-platform/schemas/model_output`

That path captures:

- gateway log and metrics
- backend metrics
- backend trace detail for sync and async flows
- backend execution-log slices from `/v1/admin/logs`, keyed by request/trace/job identity
- a machine-readable `manifest.json`
- a reviewer-fast `summary.md`

Supporting docs:

- `/Users/chranama/career/inference-serving-gateway/docs/observability-walkthrough.md`
- `/Users/chranama/career/inference-serving-gateway/docs/integrated-metrics-map.md`
- `/Users/chranama/career/inference-serving-gateway/docs/trace-identity-contract.md`
- `/Users/chranama/career/inference-serving-gateway/docs/local-environment-contract.md`

Interpretation note:

- `/v1/admin/logs` is inference-execution-focused
- async poll visibility is expected to be strongest in access logs and trace events rather than in execution-log rows

This script is intentionally not part of the default `go test` flow because it depends on a running backend environment outside this repository.
