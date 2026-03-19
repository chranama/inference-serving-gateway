# Proof Helpers

This directory contains proof helpers for the gateway in two modes:

- mock-upstream proof
- real backend integration proof

## Mock Upstream Proof

This is the canonical proof path for `inference-serving-gateway v1`.

Command:

```bash
proof/generate_mock_proof.sh
```

What it does:

- starts the local Python mock upstream
- starts the Go gateway
- captures:
  - `healthz`
  - `readyz`
  - `metrics`
  - sync extract forwarding
  - async submit forwarding
  - async status polling

Artifacts are written under:

- `proof/artifacts/mock_upstream/latest/`

Key proof files:

- `manifest.json`
- `summary.md`
- `extract.headers`
- `extract.body.json`
- `extract_jobs.headers`
- `extract_jobs.body.json`
- `job_status.headers`
- `job_status.body.json`

What this path proves:

- stable route surface for sync and async extract
- gateway-owned request and trace identity behavior
- readiness and metrics surfaces
- a reproducible local demo path independent of the real backend

## `llm-extraction-platform` Integration Probe

Command:

```bash
LLM_EXTRACTION_PLATFORM_BASE_URL=http://127.0.0.1:8000 proof/run_llm_extraction_platform_integration.sh
```

Use this only when the real backend is already running and configured.

This path is intentionally treated as:

- backend `v3` integration proof

not:

- the release gate for gateway `v1`
