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

The extract and async job artifacts should show propagated \`request_id\` and \`trace_id\` values.
EOF

echo "Generated mock proof artifacts in ${ARTIFACT_DIR}"

