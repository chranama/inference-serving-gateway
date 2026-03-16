# Proof Helpers

This directory contains proof helpers for the gateway in two modes:

- mock-upstream proof
- real backend integration proof

## Mock Upstream Proof

This is the primary proof path for the repository MVP.

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

## `llm-extraction-platform` Integration Probe

Command:

```bash
LLM_EXTRACTION_PLATFORM_BASE_URL=http://127.0.0.1:8000 proof/run_llm_extraction_platform_integration.sh
```

Use this only when the real backend is already running and configured.

