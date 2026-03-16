# Mock Upstream Proof Summary

- Upstream URL: http://127.0.0.1:18081
- Gateway URL: http://127.0.0.1:18080
- Captured files:
  - `healthz.body.json`
  - `readyz.body.json`
  - `metrics.txt`
  - `extract.body.json`
  - `extract_jobs.body.json`
  - `job_status.body.json`

The extract and async job artifacts should show propagated `request_id` and `trace_id` values.
