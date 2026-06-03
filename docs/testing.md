# Testing

The test suite is designed around the gateway boundary: configuration, route
policy, middleware behavior, upstream forwarding, observability, and end-to-end
gateway behavior with a mock upstream.

## Command

```bash
go test ./...
```

## Test Coverage

Unit tests cover:

- environment configuration loading and validation
- structured JSON error responses
- request identity assignment and preservation
- route allowlist behavior
- concurrency and rate limiter behavior
- OpenTelemetry setup and span propagation
- upstream trace-context injection

Integration tests cover:

- `/healthz`
- `/readyz` reflecting upstream readiness
- `/metrics`
- synchronous extraction forwarding
- asynchronous extraction submission and polling
- client-provided request and trace identity preservation
- gateway proxy marker header
- upstream timeout behavior
- upstream unavailable behavior
- request-size rejection
- disabled route rejection
- concurrency-limit rejection
- rate-limit rejection

The integration tests use in-process HTTP test servers, so they do not require a
running external backend.

## What Tests Do Not Cover

The default `go test ./...` suite does not run the live
`llm-extraction-platform` integration stack, the local `kind` stack, or AWS
deployment paths. Those are covered by separate scripts under `proof/` and
deployment-specific assets.
