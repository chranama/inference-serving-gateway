#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARTIFACT_DIR="${1:-${SCRIPT_DIR}/artifacts/mock_upstream/latest}"
UPSTREAM_PORT="${UPSTREAM_PORT:-18081}"
GATEWAY_PORT="${GATEWAY_PORT:-18080}"
UPSTREAM_URL="http://127.0.0.1:${UPSTREAM_PORT}"
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"

mkdir -p "${ARTIFACT_DIR}"
rm -f "${ARTIFACT_DIR}"/*

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

require_command python3
require_command curl
require_command go

cleanup() {
  if [[ -n "${GATEWAY_PID:-}" ]]; then
    kill "${GATEWAY_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${UPSTREAM_PID:-}" ]]; then
    kill "${UPSTREAM_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

python3 "${SCRIPT_DIR}/mock_upstream.py" --port "${UPSTREAM_PORT}" >"${ARTIFACT_DIR}/mock-upstream.log" 2>&1 &
UPSTREAM_PID=$!

(
  cd "${REPO_ROOT}"
  GATEWAY_LISTEN_ADDR="127.0.0.1:${GATEWAY_PORT}" \
  GATEWAY_UPSTREAM_BASE_URL="${UPSTREAM_URL}" \
  go run ./cmd/gateway >"${ARTIFACT_DIR}/gateway.log" 2>&1
) &
GATEWAY_PID=$!

wait_for_url() {
  local url="$1"
  for _ in $(seq 1 50); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

wait_for_url "${GATEWAY_URL}/healthz"
wait_for_url "${GATEWAY_URL}/readyz"

curl -fsS -D "${ARTIFACT_DIR}/healthz.headers" "${GATEWAY_URL}/healthz" >"${ARTIFACT_DIR}/healthz.body.json"
curl -fsS -D "${ARTIFACT_DIR}/readyz.headers" "${GATEWAY_URL}/readyz" >"${ARTIFACT_DIR}/readyz.body.json"
curl -fsS -D "${ARTIFACT_DIR}/metrics.headers" "${GATEWAY_URL}/metrics" >"${ARTIFACT_DIR}/metrics.txt"

EXTRACT_PAYLOAD='{"schema_id":"demo_schema_v1","text":"Vendor: ACME\nTotal: 10.00"}'
curl -fsS \
  -D "${ARTIFACT_DIR}/extract.headers" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: proof-request-1" \
  -H "X-Trace-ID: proof-trace-1" \
  -d "${EXTRACT_PAYLOAD}" \
  "${GATEWAY_URL}/v1/extract" >"${ARTIFACT_DIR}/extract.body.json"

curl -fsS \
  -D "${ARTIFACT_DIR}/extract_jobs.headers" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: proof-request-2" \
  -H "X-Trace-ID: proof-trace-2" \
  -d "${EXTRACT_PAYLOAD}" \
  "${GATEWAY_URL}/v1/extract/jobs" >"${ARTIFACT_DIR}/extract_jobs.body.json"

JOB_ID="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["job_id"])' \
    "${ARTIFACT_DIR}/extract_jobs.body.json"
)"

curl -fsS \
  -D "${ARTIFACT_DIR}/job_status.headers" \
  -H "X-Request-ID: proof-request-3" \
  -H "X-Trace-ID: proof-trace-2" \
  "${GATEWAY_URL}/v1/extract/jobs/${JOB_ID}" >"${ARTIFACT_DIR}/job_status.body.json"

ARTIFACT_DIR_ENV="${ARTIFACT_DIR}" GATEWAY_URL_ENV="${GATEWAY_URL}" UPSTREAM_URL_ENV="${UPSTREAM_URL}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

artifact_dir = Path(os.environ["ARTIFACT_DIR_ENV"])

def read_json(name: str):
    return json.loads((artifact_dir / name).read_text())

def read_text(name: str):
    return (artifact_dir / name).read_text()

def header_map(name: str):
    out = {}
    for line in read_text(name).splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        out[key.strip().lower()] = value.strip()
    return out

healthz = read_json("healthz.body.json")
readyz = read_json("readyz.body.json")
extract = read_json("extract.body.json")
extract_jobs = read_json("extract_jobs.body.json")
job_status = read_json("job_status.body.json")

extract_headers = header_map("extract.headers")
extract_jobs_headers = header_map("extract_jobs.headers")
job_status_headers = header_map("job_status.headers")
metrics = read_text("metrics.txt")

checks = {
    "healthz_ok": healthz == {"status": "ok"},
    "readyz_ready": readyz == {"status": "ready"},
    "metrics_include_gateway_requests_total": "gateway_requests_total" in metrics,
    "metrics_include_gateway_upstream_requests_total": "gateway_upstream_requests_total" in metrics,
    "extract_request_id_preserved": extract.get("request_id") == "proof-request-1",
    "extract_trace_id_preserved": extract.get("trace_id") == "proof-trace-1",
    "extract_header_request_id_preserved": extract_headers.get("x-request-id") == "proof-request-1",
    "extract_header_trace_id_preserved": extract_headers.get("x-trace-id") == "proof-trace-1",
    "async_submit_request_id_preserved": extract_jobs.get("request_id") == "proof-request-2",
    "async_submit_trace_id_preserved": extract_jobs.get("trace_id") == "proof-trace-2",
    "async_submit_header_request_id_preserved": extract_jobs_headers.get("x-request-id") == "proof-request-2",
    "async_submit_header_trace_id_preserved": extract_jobs_headers.get("x-trace-id") == "proof-trace-2",
    "async_status_request_id_reflects_poll_request": job_status.get("request_id") == "proof-request-3",
    "async_status_trace_id_preserved": job_status.get("trace_id") == "proof-trace-2",
    "async_status_header_request_id_reflects_poll_request": job_status_headers.get("x-request-id") == "proof-request-3",
    "async_status_header_trace_id_preserved": job_status_headers.get("x-trace-id") == "proof-trace-2",
}

failed = [name for name, ok in checks.items() if not ok]
manifest = {
    "mode": "mock_upstream",
    "gateway_url": os.environ["GATEWAY_URL_ENV"],
    "upstream_url": os.environ["UPSTREAM_URL_ENV"],
    "checks": checks,
    "artifacts": {
        "healthz_body": "healthz.body.json",
        "readyz_body": "readyz.body.json",
        "metrics": "metrics.txt",
        "extract_headers": "extract.headers",
        "extract_body": "extract.body.json",
        "extract_jobs_headers": "extract_jobs.headers",
        "extract_jobs_body": "extract_jobs.body.json",
        "job_status_headers": "job_status.headers",
        "job_status_body": "job_status.body.json",
        "gateway_log": "gateway.log",
        "mock_upstream_log": "mock-upstream.log",
    },
    "expected_identity": {
        "extract": {"request_id": "proof-request-1", "trace_id": "proof-trace-1"},
        "extract_jobs": {"request_id": "proof-request-2", "trace_id": "proof-trace-2"},
        "job_status": {"request_id": "proof-request-3", "trace_id": "proof-trace-2"},
    },
}

(artifact_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

if failed:
    print("Mock proof validation failed:")
    for name in failed:
        print(f" - {name}")
    sys.exit(1)
PY

cat >"${ARTIFACT_DIR}/summary.md" <<EOF
# Mock Upstream Proof Summary

- Upstream URL: ${UPSTREAM_URL}
- Gateway URL: ${GATEWAY_URL}
- Captured files:
  - \`healthz.body.json\`
  - \`readyz.body.json\`
  - \`metrics.txt\`
  - \`extract.body.json\`
  - \`extract_jobs.body.json\`
  - \`job_status.body.json\`
  - \`manifest.json\`

Validated expectations:

- sync extract preserves \`proof-request-1\` and \`proof-trace-1\`
- async submit preserves \`proof-request-2\` and \`proof-trace-2\`
- async status polling preserves \`proof-trace-2\` while reflecting the poll request as \`proof-request-3\`
- metrics include both edge and upstream counters

Use \`manifest.json\` as the machine-readable proof contract for the mock-upstream v1 demo path.
EOF

echo "Generated mock proof artifacts in ${ARTIFACT_DIR}"
