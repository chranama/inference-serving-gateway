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
  - `manifest.json`

Validated expectations:

- sync extract preserves `proof-request-1` and `proof-trace-1`
- async submit preserves `proof-request-2` and `proof-trace-2`
- async status polling preserves `proof-trace-2` while reflecting the poll request as `proof-request-3`
- metrics include both edge and upstream counters

Use `manifest.json` as the machine-readable proof contract for the mock-upstream v1 demo path.
