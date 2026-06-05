# Mock Compose OTel Proof Summary

- Gateway URL: http://127.0.0.1:18086
- Jaeger URL: http://127.0.0.1:16687
- Checks passed: 16
- Checks failed: 0

## Checks

- pass: `healthz_ok`
- pass: `readyz_ready`
- pass: `collector_health_ok`
- pass: `extract_ok`
- pass: `request_id_preserved`
- pass: `trace_id_preserved`
- pass: `traceparent_reached_mock_upstream`
- pass: `gateway_log_shows_otel_enabled`
- pass: `collector_received_trace_data`
- pass: `jaeger_gateway_service_registered`
- pass: `jaeger_trace_found`
- pass: `jaeger_trace_has_gateway_service`
- pass: `jaeger_trace_contains_gateway_server_span`
- pass: `jaeger_trace_contains_upstream_client_span`
- pass: `jaeger_trace_has_request_id_attribute`
- pass: `jaeger_trace_has_trace_id_attribute`

## Failed Checks

- none
