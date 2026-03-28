# OpenTelemetry Contract

This document defines the Phase 2.2 tracing contract for `inference-serving-gateway`.

## Scope

At this stage, the gateway has the bounded Phase 2.2.2 tracing path:

- SDK dependency baseline is present
- W3C propagation is configured
- OTLP/HTTP exporter configuration is defined
- inbound gateway request spans are emitted
- upstream backend calls emit client spans and inject W3C trace context
- tracing can be enabled or disabled without changing request behavior

## Identity Model

The gateway keeps two tracing concepts separate:

- OpenTelemetry `TraceId` / `SpanId`
- application `trace_id`

They are not interchangeable.

Application identity remains authoritative for the existing system:

- `X-Request-ID` = concrete request identity
- `X-Trace-ID` = logical operation identity

OpenTelemetry adds a standard distributed-tracing carrier around that model.

## Propagation

The gateway uses standard W3C propagation:

- `traceparent`
- `tracestate` when present
- baggage propagation

Existing application headers remain in place:

- `X-Request-ID`
- `X-Trace-ID`

Gateway spans carry the application identifiers as span attributes rather than deriving them from the OTel `TraceId`.

## Export Protocol

The first bounded rollout uses OTLP over HTTP.

The exporter endpoint should be a full absolute traces URL, for example:

- `http://127.0.0.1:4318/v1/traces`

## Environment Variables

- `GATEWAY_OTEL_ENABLED`
- `GATEWAY_OTEL_SERVICE_NAME`
- `GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT`

## Runtime Safety Rule

Tracing bootstrap must be safe when disabled.

Current behavior:

- if `GATEWAY_OTEL_ENABLED` is false, the gateway runs normally without an exporter
- if tracing is enabled but `GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT` is empty, the gateway logs a warning and runs without an exporter
- invalid OTLP endpoint configuration is rejected at startup

## Current Default

The default gateway OTel service name is:

- `inference-serving-gateway`

Later slices will extend the trace path into the backend API and async worker.
