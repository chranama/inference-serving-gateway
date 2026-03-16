# `llm-extraction-platform` Integration Notes

This repository is intentionally built against a mock upstream first.

The real backend integration target is:

- `llm-extraction-platform`

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

## Manual Integration Proof

Use:

```bash
proof/run_llm_extraction_platform_integration.sh
```

Required environment:

- `LLM_EXTRACTION_PLATFORM_BASE_URL`

The script is designed to:

- start the gateway against the real backend
- issue sync extract requests through the gateway
- issue async submit and poll requests through the gateway
- preserve and surface request/trace identifiers in saved artifacts

This script is intentionally not part of the default `go test` flow because it depends on a running backend environment outside this repository.

