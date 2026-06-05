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
`llm-extraction-platform` integration stack, Docker Compose proof path, isolated
`kind` proof path, integrated `kind` stack, or AWS deployment paths. Those are
covered by separate scripts under `proof/` and deployment-specific assets.

## Proof Workflows

Use the proof workflows when the question is not only "does the code pass unit
tests?" but "what runtime behavior can a reviewer inspect?"

Host process proof:

```bash
make proof-host
```

Docker Compose proof:

```bash
make proof-compose
```

Isolated OpenTelemetry proof:

```bash
make proof-otel
```

Isolated Kubernetes proof:

```bash
make proof-kind-up
make proof-kind
make proof-kind-down
```

Integrated backend proof:

```bash
proof/run_local_stack.sh proof
proof/run_kind_stack.sh proof
```

The Compose proof is the broadest isolated artifact set for gateway-owned edge
behavior. It captures forwarding, identity, metrics, timeout, upstream
unavailable, request-size rejection, route-policy rejection, concurrency
rejection, rate-limit rejection, unsupported-route rejection, async-route
toggles, metrics-disabled behavior, and per-phase runtime config.

The isolated OpenTelemetry proof validates OTLP/HTTP export, Jaeger trace
availability, gateway server and upstream client spans, and W3C trace-context
injection into the mock upstream request.
