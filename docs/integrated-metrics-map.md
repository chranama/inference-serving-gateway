# Phase 1 Metrics Map

This document maps the most important Phase 1 observability signals across:

- `inference-serving-gateway`
- `llm-extraction-platform`

The goal is not metric-name unification at all costs.
The goal is fast reviewer understanding of what each layer owns.

## Gateway Metrics

These metrics describe edge/runtime behavior.

### Traffic and latency

- `gateway_requests_total`
- `gateway_request_duration_seconds`

Use these when you want to answer:

- what routes hit the gateway
- how much traffic the edge is handling
- how much latency the edge adds

### Upstream behavior

- `gateway_upstream_requests_total`
- `gateway_upstream_request_duration_seconds`

Use these when you want to answer:

- whether the gateway reached the backend
- whether upstream calls succeeded, timed out, or failed
- how upstream latency compares to total gateway latency

### Edge-owned rejections

- `gateway_edge_errors_total`

Use this when you want to answer:

- what the gateway rejected before the backend handled the request
- which policies or limits fired at the edge

## Backend Metrics

These metrics describe inference application behavior.

### API traffic and latency

- `llm_api_request_total`
- `llm_api_request_latency_seconds`

Use these when you want to answer:

- what traffic reached the backend
- which backend routes and models were exercised
- how backend latency behaves independently of edge latency

### Extraction behavior

- `llm_extraction_requests_total`
- `llm_extraction_validation_failures_total`
- `llm_extraction_repair_total`

Use these when you want to answer:

- how extraction traffic behaves
- where validation failures occur
- whether repair logic is firing and how often

### Runtime and queue behavior

Examples already present in the backend:

- `llm_generate_queue_depth`
- `llm_generate_in_flight`
- `llm_generate_queue_wait_seconds`
- `llm_generate_execution_seconds`
- loader/runtime state metrics in `server/src/llm_server/services/llm_runtime/metrics.py`

Use these when you want to answer:

- what is happening inside the inference service
- whether work is waiting, executing, or blocked
- what runtime state the service is in

## Correlation Rules

Phase 1 correlation should be read like this:

1. Start with gateway request and upstream metrics to confirm traffic passed through the edge.
2. Use gateway `request_id` and `trace_id` from logs and response headers.
3. Use backend request metrics and backend admin traces to confirm application-level execution.
4. Use async trace events to connect submit, worker execution, and polling behavior.

## Ownership Summary

Use gateway metrics to reason about:

- admission
- edge latency
- upstream health
- edge-owned failures

Use backend metrics to reason about:

- application latency
- extraction semantics
- validation/repair behavior
- queue and worker execution

That split is the main point of the integrated observability story.
