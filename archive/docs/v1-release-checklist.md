# v1 Release Checklist

Use this checklist before calling `inference-serving-gateway v1` complete.

This checklist is for the gateway release in isolation.
It is not the integrated `llm-extraction-platform v3` checklist.

Reference:

- [`v1-rollout-plan.md`](v1-rollout-plan.md)

## Contract Surface

- `POST /v1/extract` is implemented and tested
- `POST /v1/extract/jobs` is implemented and tested
- `GET /v1/extract/jobs/{job_id}` is implemented and tested
- `GET /healthz` is implemented and tested
- `GET /readyz` is implemented and tested
- `GET /metrics` is implemented and tested

## Identity Contract

- gateway preserves client-provided `X-Request-ID`
- gateway preserves client-provided `X-Trace-ID`
- gateway generates missing request and trace IDs
- gateway response headers include canonical `X-Request-ID`
- gateway response headers include canonical `X-Trace-ID`
- async status polling preserves the original trace identity

## Edge Runtime Controls

- request-size admission is tested
- route policy toggles are tested
- timeout behavior is tested
- concurrency limiting is tested
- rate limiting is tested
- readiness reflects upstream readiness

## Proof Path

- [`../proof/generate_mock_proof.sh`](../proof/generate_mock_proof.sh) runs successfully
- mock proof artifacts are generated under `proof/artifacts/mock_upstream/latest/`
- `manifest.json` passes all checks
- `summary.md` explains the identity expectations clearly

## Local Development Story

- [`local-development.md`](local-development.md) clearly identifies the primary local workflow
- mock-upstream workflow is documented as the canonical `v1` path
- Docker Compose alternative is documented but secondary

## Deferred Items Are Explicit

- backend `X-Trace-ID` support is deferred to `llm-extraction-platform v3`
- backend trust mode is deferred to `llm-extraction-platform v3`
- async backend trace persistence is deferred to `llm-extraction-platform v3`
- real backend integration proof is deferred to `llm-extraction-platform v3`
- full edge-auth migration is deferred beyond `v1`

## Final Gate

- `go test ./...` passes
- docs match actual behavior
- the repo can be described honestly as:
  - a stable edge/runtime MVP with a frozen route and identity contract
