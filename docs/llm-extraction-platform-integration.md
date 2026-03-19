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

This script is intentionally not part of the default `go test` flow because it depends on a running backend environment outside this repository.
