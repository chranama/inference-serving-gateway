#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${LLM_EXTRACTION_PLATFORM_BASE_URL:-}" ]]; then
  echo "Set LLM_EXTRACTION_PLATFORM_BASE_URL before running this script."
  exit 1
fi

ARTIFACT_DIR="${1:-${SCRIPT_DIR}/artifacts/llm_extraction_platform/latest}"
GATEWAY_PORT="${GATEWAY_PORT:-18082}"
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"

mkdir -p "${ARTIFACT_DIR}"

cleanup() {
  if [[ -n "${GATEWAY_PID:-}" ]]; then
    kill "${GATEWAY_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

(
  cd "${REPO_ROOT}"
  GATEWAY_LISTEN_ADDR="127.0.0.1:${GATEWAY_PORT}" \
  GATEWAY_UPSTREAM_BASE_URL="${LLM_EXTRACTION_PLATFORM_BASE_URL}" \
  go run ./cmd/gateway >"${ARTIFACT_DIR}/gateway.log" 2>&1
) &
GATEWAY_PID=$!

wait_for_url() {
  local url="$1"
  for _ in $(seq 1 80); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_for_url "${GATEWAY_URL}/healthz"

EXTRACT_PAYLOAD='{"schema_id":"sroie_receipt_v1","text":"Vendor: ACME\nTotal: 10.00","cache":false,"repair":true}'

curl -fsS \
  -D "${ARTIFACT_DIR}/extract.headers" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: integration-request-1" \
  -H "X-Trace-ID: integration-trace-1" \
  -d "${EXTRACT_PAYLOAD}" \
  "${GATEWAY_URL}/v1/extract" >"${ARTIFACT_DIR}/extract.body.json"

curl -fsS \
  -D "${ARTIFACT_DIR}/extract_jobs.headers" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: integration-request-2" \
  -H "X-Trace-ID: integration-trace-2" \
  -d "${EXTRACT_PAYLOAD}" \
  "${GATEWAY_URL}/v1/extract/jobs" >"${ARTIFACT_DIR}/extract_jobs.body.json"

JOB_ID="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["job_id"])' \
    "${ARTIFACT_DIR}/extract_jobs.body.json"
)"

curl -fsS \
  -D "${ARTIFACT_DIR}/job_status.headers" \
  -H "X-Request-ID: integration-request-3" \
  -H "X-Trace-ID: integration-trace-2" \
  "${GATEWAY_URL}/v1/extract/jobs/${JOB_ID}" >"${ARTIFACT_DIR}/job_status.body.json"

echo "Generated llm-extraction-platform integration artifacts in ${ARTIFACT_DIR}"

