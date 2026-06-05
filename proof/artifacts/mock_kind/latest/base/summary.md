# mock_kind:base Probe Summary

- Gateway URL: http://127.0.0.1:18085
- Scenarios: base, concurrency
- Checks passed: 13
- Checks failed: 0

## Checks

- pass: `healthz_ok`
- pass: `readyz_ready`
- pass: `metrics_available`
- pass: `metrics_include_gateway_requests_total`
- pass: `metrics_include_gateway_upstream_requests_total`
- pass: `generated_identity_response_body`
- pass: `generated_identity_response_headers`
- pass: `provided_extract_identity_preserved`
- pass: `async_submit_identity_preserved`
- pass: `async_status_identity_preserved`
- pass: `concurrency_first_request_completed`
- pass: `concurrency_second_request_rejected`
- pass: `concurrency_metrics_include_edge_error`

Use `manifest.json` as the machine-readable proof contract for this probe.
