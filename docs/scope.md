# Scope

This repository is a bounded gateway service for inference-backed extraction
workflows.

## Current Claims

The current implementation supports:

- a runnable Go HTTP gateway
- health, readiness, and Prometheus metrics
- sync and async extraction forwarding routes
- request and trace identity preservation
- OpenTelemetry trace propagation
- structured edge errors
- route allowlist behavior
- request-size limits
- timeout handling
- concurrency and rate limiting
- unit and integration tests
- mock-upstream and backend-integrated runtime artifacts

## Non-Claims

This repository does not claim:

- full edge authentication or API-key ownership
- multi-tenant routing
- dynamic model routing
- `POST /v1/generate`
- production autoscaling
- high availability
- production traffic hardening
- ownership of extraction semantics or backend job state

## Deferred Work

Future work could include:

- gateway-owned authentication and authorization
- broader route support
- tenant-aware limits
- dynamic upstream selection
- cloud deployment hardening
- automated cross-repo integration CI

Those are outside the current gateway boundary unless implemented and covered by
tests or artifacts.
