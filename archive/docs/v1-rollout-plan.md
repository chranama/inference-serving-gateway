# v1 Rollout Plan

This document turns the existing service-boundary contract into a practical rollout plan for:

- `inference-serving-gateway`
- `llm-extraction-platform`

Primary contract source:

- [`../../llm-extraction-platform/docs/service-boundary.inference-serving-gateway.md`](../../llm-extraction-platform/docs/service-boundary.inference-serving-gateway.md)

## 1. Release Split

This plan now assumes two explicit milestones:

1. `inference-serving-gateway v1`
   - implemented and released in isolation
   - validated against the mock upstream
   - treated as the stable edge/runtime contract
2. `llm-extraction-platform v3`
   - implements compatibility with gateway `v1`
   - preserves standalone backend mode
   - proves real end-to-end integration

This means:

- gateway `v1` is **not** defined by real-backend integration being complete
- backend compatibility and integrated proof move into the `llm-extraction-platform v3` milestone

## 2. Recommended Definition Of `inference-serving-gateway v1`

Recommended gateway `v1` scope:

- `inference-serving-gateway` exposes and stabilizes:
  - `POST /v1/extract`
  - `POST /v1/extract/jobs`
  - `GET /v1/extract/jobs/{job_id}`
  - `GET /healthz`
  - `GET /readyz`
- `GET /metrics`
- the gateway preserves the contract shape expected by the backend integration:
  - request identity continuity
  - trace identity continuity
  - async route continuity
  - backend-owned extraction semantics
  - gateway-owned edge/runtime behavior
- mock-upstream proof is sufficient for release
- real-backend integration is intentionally deferred to `llm-extraction-platform v3`

Recommended non-goals for gateway `v1`:

- `POST /v1/generate`
- moving extraction semantics into the gateway
- requiring `llm-extraction-platform` compatibility work to be finished first
- large auth redesign beyond what is needed to keep the contract coherent

## 3. Recommended Definition Of `llm-extraction-platform v3`

Recommended `llm-extraction-platform v3` scope:

- preserve standalone backend mode
- add the compatibility work needed to run cleanly behind gateway `v1`
- prove end-to-end sync and async behavior through the gateway
- preserve backend ownership of:
  - extraction semantics
  - async job execution
  - trace-detail recording
  - admin/debugging surfaces

Recommended non-goals for backend `v3`:

- requiring the gateway for normal operation
- moving business logic or extraction semantics out of the backend
- full auth migration to the gateway

## 4. Current State Assessment

## Gateway Repository

Implemented now:

- runnable Go HTTP service
- route coverage for sync extract, async submit, async status, health, readiness, and metrics
- request and trace propagation middleware
- `X-Gateway-Proxy: inference-serving-gateway` on upstream requests
- timeout handling
- request-size admission control
- concurrency and rate limits
- mock-upstream proof scripts
- passing Go unit and integration tests

Evidence:

- [`../README.md`](../README.md)
- [`../internal/httpapi/handler.go`](../internal/httpapi/handler.go)
- [`../internal/upstream/client.go`](../internal/upstream/client.go)
- [`../proof/run_llm_extraction_platform_integration.sh`](../proof/run_llm_extraction_platform_integration.sh)

Assessment:

- the gateway MVP is real and already close to a standalone `v1`
- most remaining gateway `v1` work is proof, packaging, and contract hardening
- most real-backend work belongs to the later backend `v3` milestone

## Backend Repository

Implemented now:

- standalone extract service
- sync extract and async extract job routes
- backend-owned async job persistence and execution
- request and trace handling through:
  - `X-Request-ID`
  - `X-Trace-ID`
  - `EDGE_MODE=behind_gateway`
- separate persisted `trace_id` for async jobs
- trace-event recording and trace-detail inspection
- stable `healthz` and `readyz` endpoints
- live gateway-backed proof for sync and async flows

Evidence:

- [`../../llm-extraction-platform/docs/service-boundary.inference-serving-gateway.md`](../../llm-extraction-platform/docs/service-boundary.inference-serving-gateway.md)
- [`../../llm-extraction-platform/server/src/llm_server/main.py`](../../llm-extraction-platform/server/src/llm_server/main.py)
- [`../../llm-extraction-platform/server/src/llm_server/api/extract.py`](../../llm-extraction-platform/server/src/llm_server/api/extract.py)
- [`../../llm-extraction-platform/server/src/llm_server/services/extract_jobs.py`](../../llm-extraction-platform/server/src/llm_server/services/extract_jobs.py)

Assessment:

- the backend already has the right route surface
- the backend is now gateway-aware for `v3`
- sync and async trace continuity work with separate request and trace identity
- backend auth remains intentionally authoritative for the split release

## 5. Contract Alignment Read

### Already aligned

- gateway route surface matches planned `v1`
- backend route surface matches planned `v1`
- gateway preserves standalone backend architecture
- gateway adds edge concerns without taking over extraction semantics
- gateway readiness depends on upstream readiness
- request identity continuity across sync and async paths
- distinct `trace_id` continuity across sync and async paths
- backend gateway-aware config mode:
  - `EDGE_MODE=behind_gateway`
- async job persistence of a distinct `trace_id`
- repeatable real-backend integration proof

### Still intentionally deferred

- full edge-auth migration
- canonical cross-repo CI lane for the live proof

## 6. Remaining Optional Follow-Up After The Split Rollout

## A. Cross-repo CI automation

Current state:

- the live backend proof is repeatable
- it is still manual and intentionally outside the default `go test` flow

## B. Edge-auth migration remains deferred

- the gateway still forwards `X-API-Key`
- backend auth remains authoritative by design for `v1` + `v3`
- moving auth fully into the gateway is deferred beyond the current split release

## 7. What Is Needed For `inference-serving-gateway v1`

## Required in `inference-serving-gateway`

### 1. Stabilize the route and identity contract

Keep the gateway contract explicit and tested for:

- `POST /v1/extract`
- `POST /v1/extract/jobs`
- `GET /v1/extract/jobs/{job_id}`
- `GET /healthz`
- `GET /readyz`
- `GET /metrics`
- `X-Request-ID`
- `X-Trace-ID`
- `X-Gateway-Proxy`

### 2. Promote mock-upstream proof to canonical status

Needed:

- documented local runbook for mock-upstream proof
- expected artifacts for sync and async flows
- proof output that clearly shows request and trace continuity

### 3. Strengthen local deployment story

Provide one canonical developer path for:

- gateway + mock upstream

This can remain:

- compose-based
- or script-based

as long as it is the obvious supported local path.

### 4. Freeze deferred items explicitly

Gateway `v1` should document that these are deferred to backend `v3`:

- backend trust mode
- backend `X-Trace-ID` support
- async trace persistence in backend storage
- integrated proof against the real backend

## 8. What Is Needed For `llm-extraction-platform v3`

## Required in `llm-extraction-platform`

### 1. Add explicit gateway-aware config mode

Implement one of:

- `TRUST_GATEWAY_HEADERS=true`
- `EDGE_MODE=behind_gateway`

Minimum behavior:

- preserve standalone mode by default
- in gateway-backed mode, trust gateway-provided request and trace headers

### 2. Accept inbound `X-Trace-ID`

Update request context initialization so:

- `X-Request-ID` and `X-Trace-ID` are read independently
- `trace_id` defaults to `request_id` only when `X-Trace-ID` is absent

### 3. Persist async `trace_id`

Add `trace_id` to `ExtractJob` and related serialization.

Required follow-through:

- job creation stores both `request_id` and `trace_id`
- submit responses return the persisted `trace_id`
- status polling uses the persisted `trace_id`
- trace events for async lifecycle use the persisted `trace_id`

### 4. Emit `X-Trace-ID` response header

Sync and async responses should expose:

- `X-Request-ID`
- `X-Trace-ID`

The body and headers should agree on trace identity.

### 5. Add gateway-backed tests

At minimum:

- distinct request/trace IDs on sync extract
- distinct request/trace IDs on async submit
- status polling preserves the same `trace_id`
- standalone mode still works

## Required in `inference-serving-gateway`

### 1. Promote real-backend integration proof from optional to canonical for backend `v3`

The current manual script is useful but not yet the canonical integrated proof story.

Needed:

- documented local runbook for real backend integration
- expected artifacts for sync and async flows
- proof output that shows request and trace continuity clearly

### 2. Add integrated local stack story

Provide one canonical developer path for:

- gateway + real backend

This could be:

- a compose stack
- a launcher script
- or a documented two-process workflow with exact commands

### 3. Add assertions for backend contract compatibility

The gateway should verify not just transport success, but the expected identity behavior:

- request ID present
- trace ID present
- async status polling preserves trace continuity

## Required across both repos

### 1. Canonical end-to-end proof artifacts

For the integrated backend `v3` release, keep one reproducible artifact set showing:

- sync extract through the gateway
- async submit through the gateway
- async poll through the gateway
- request ID continuity
- trace ID continuity

### 2. Cross-repo validation lane

At minimum, one of:

- a documented manual release gate
- a scripted integration lane
- or a CI job that runs when both repos are available together

### 3. Release checklist

Before calling backend `v3` complete, verify:

- standalone backend mode still passes
- gateway-backed mode passes
- async trace continuity is real
- health/readiness behavior is stable
- docs reflect the actual trust and auth behavior

## 9. Recommended Rollout Phases

## Phase 0. Freeze the split release scope

Decide and document:

- gateway `v1` excludes `POST /v1/generate`
- gateway `v1` is isolation-first and mock-upstream-valid
- backend `v3` owns real integration
- backend auth remains authoritative
- distinct `trace_id` continuity is required for backend `v3`

Exit condition:

- both milestone boundaries are written down and not ambiguous

## Phase 1. Finish `inference-serving-gateway v1` in isolation

Implement and harden:

- mock-proof artifacts
- local gateway + mock upstream workflow
- route and identity contract tests
- clear docs on deferred backend integration items

Exit condition:

- the gateway can be described as a stable standalone edge/runtime MVP with a frozen contract

## Phase 2. Backend compatibility work for `llm-extraction-platform v3`

Implement:

- gateway-aware config mode
- independent inbound `X-Trace-ID`
- async `trace_id` persistence
- response header alignment
- tests

Exit condition:

- backend can run both standalone and gateway-backed without ambiguity

## Phase 3. Real backend integration in the gateway repo

Promote:

- real-backend proof script
- local integration workflow
- proof artifact expectations

Exit condition:

- a fresh local run produces stable gateway-to-backend proof artifacts

## Phase 4. Cross-repo validation

Add:

- a repeatable validation lane
- documentation for operators and developers

Exit condition:

- the integration can be revalidated without bespoke setup knowledge

## Phase 5. Release and portfolio hardening

Finalize:

- docs wording
- demo/proof screenshots or artifacts
- recruiter-safe explanation of the boundary and rollout

Exit condition:

- the project can be described as a real integrated edge/runtime system, not only an isolated MVP

## 10. Exit Criteria For `inference-serving-gateway v1`

Gateway `v1` is done when all of these are true:

1. the gateway exposes the planned route surface
2. mock-upstream sync and async flows pass cleanly
3. `X-Request-ID` continuity is preserved at the gateway boundary
4. `X-Trace-ID` continuity is preserved at the gateway boundary
5. local proof artifacts exist and are reproducible
6. deferred backend-integration assumptions are documented explicitly

## 11. Exit Criteria For `llm-extraction-platform v3`

Backend `v3` is done when all of these are true:

1. the gateway fronts the real backend for sync and async extract paths
2. the backend still works cleanly without the gateway
3. `X-Request-ID` continuity is preserved end to end
4. `X-Trace-ID` continuity is preserved end to end
5. async job polling preserves the original trace identity
6. docs describe the real integration accurately

## 12. Current Recommendation

The contract is strong enough to support a real `v1` rollout plan now.

Best concise assessment:

- the gateway repo is already at a credible isolation-first `v1`
- the backend route surface is already compatible enough to target a later `v3`
- the main work left for backend `v3` is gateway-awareness and integrated proof

If scope is kept disciplined, this is a realistic next milestone.

If scope expands to include full auth migration at the edge, it becomes a larger `v1.1` or `v2` effort.
