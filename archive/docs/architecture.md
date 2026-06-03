# Architecture Notes

## Goal

`inference-serving-gateway` is intended to serve as the edge/runtime layer in front of inference backends.

For the initial portfolio design:
- the gateway will be implemented in isolation
- `llm-extraction-platform` remains the canonical inference backend
- future integration will preserve standalone backend operation

## Primary Responsibilities

- validate and admit requests at the edge
- assign or propagate request and trace identifiers
- apply timeout budgets and cancellation
- enforce route/model allowlists
- enforce concurrency and rate limits
- forward requests to upstream inference backends
- expose edge metrics, logs, and readiness

## Non-Goals

- extraction semantics
- async job execution ownership
- schema validation/repair business logic
- backend trace-detail ownership

Those remain owned by `llm-extraction-platform`.

## Initial Deployment Story

### Isolation phase

```text
Client -> inference-serving-gateway -> Mock Upstream
```

### Future integration phase

```text
Client -> inference-serving-gateway -> llm-extraction-platform
```

## Design Constraint

The gateway must be useful without requiring changes to the backend first. That means:
- clean HTTP forwarding behavior
- explicit edge-owned concerns
- minimal assumptions about upstream behavior beyond the documented contract

## Canonical Integration Reference

See:
- [`../../llm-extraction-platform/docs/service-boundary.inference-serving-gateway.md`](../../llm-extraction-platform/docs/service-boundary.inference-serving-gateway.md)
