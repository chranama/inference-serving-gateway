# Documentation

This directory contains the current technical documentation for
`inference-serving-gateway`.

Start with the root [`README.md`](../README.md). Use these documents when you
want more detail about system structure, API behavior, backend integration,
tests, local operation, artifacts, or scope boundaries.

## Documents

- [Architecture](architecture.md): service shape, request flow, and ownership boundaries.
- [API](api.md): endpoint surface, headers, errors, and runtime configuration.
- [OpenAPI](openapi.yaml): static OpenAPI contract for the gateway-owned API surface.
- [Backend Integration](backend-integration.md): how the gateway works with `llm-extraction-platform`.
- [Testing](testing.md): test layout, behavior coverage, and commands.
- [Runbook](runbook.md): start, verify, observe, and shut down local workflows.
- [Artifacts](artifacts.md): generated runtime artifacts and how to interpret them.
- [Scope](scope.md): current claims, non-claims, and known limits.

Archived documentation lives in [`../archive/docs/`](../archive/docs/). Treat it
as historical context, not as current implementation guidance.
