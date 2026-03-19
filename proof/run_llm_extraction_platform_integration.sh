#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${LLM_EXTRACTION_PLATFORM_BASE_URL:-}" ]]; then
  echo "Set LLM_EXTRACTION_PLATFORM_BASE_URL before running this script."
  exit 1
fi

if [[ -z "${LLM_EXTRACTION_PLATFORM_API_KEY:-}" ]]; then
  echo "Set LLM_EXTRACTION_PLATFORM_API_KEY before running this script."
  exit 1
fi

ARTIFACT_DIR="${1:-${SCRIPT_DIR}/artifacts/llm_extraction_platform/latest}"
GATEWAY_PORT="${GATEWAY_PORT:-18082}"
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"
POLL_ATTEMPTS="${POLL_ATTEMPTS:-80}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-0.25}"

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
  -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_API_KEY}" \
  -H "X-Request-ID: integration-request-1" \
  -H "X-Trace-ID: integration-trace-1" \
  -d "${EXTRACT_PAYLOAD}" \
  "${GATEWAY_URL}/v1/extract" >"${ARTIFACT_DIR}/extract.body.json"

curl -fsS \
  -D "${ARTIFACT_DIR}/extract_jobs.headers" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_API_KEY}" \
  -H "X-Request-ID: integration-request-2" \
  -H "X-Trace-ID: integration-trace-2" \
  -d "${EXTRACT_PAYLOAD}" \
  "${GATEWAY_URL}/v1/extract/jobs" >"${ARTIFACT_DIR}/extract_jobs.body.json"

JOB_ID="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["job_id"])' \
    "${ARTIFACT_DIR}/extract_jobs.body.json"
)"

FINAL_STATUS=""
TMP_STATUS_HEADERS="${ARTIFACT_DIR}/job_status.tmp.headers"
TMP_STATUS_BODY="${ARTIFACT_DIR}/job_status.tmp.body.json"

for _ in $(seq 1 "${POLL_ATTEMPTS}"); do
  curl -fsS \
    -D "${TMP_STATUS_HEADERS}" \
    -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_API_KEY}" \
    -H "X-Request-ID: integration-request-3" \
    -H "X-Trace-ID: integration-trace-2" \
    "${GATEWAY_URL}/v1/extract/jobs/${JOB_ID}" >"${TMP_STATUS_BODY}"

  mv "${TMP_STATUS_HEADERS}" "${ARTIFACT_DIR}/job_status.headers"
  mv "${TMP_STATUS_BODY}" "${ARTIFACT_DIR}/job_status.body.json"

  FINAL_STATUS="$(
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' \
      "${ARTIFACT_DIR}/job_status.body.json"
  )"

  if [[ "${FINAL_STATUS}" == "succeeded" || "${FINAL_STATUS}" == "failed" ]]; then
    break
  fi

  sleep "${POLL_INTERVAL_SECONDS}"
done

if [[ "${FINAL_STATUS}" != "succeeded" && "${FINAL_STATUS}" != "failed" ]]; then
  echo "Timed out waiting for terminal async job state for ${JOB_ID}." >&2
  exit 1
fi

if [[ "${FINAL_STATUS}" != "succeeded" ]]; then
  echo "Async job ${JOB_ID} finished with status ${FINAL_STATUS}." >&2
  exit 1
fi

echo "Generated llm-extraction-platform integration artifacts in ${ARTIFACT_DIR}"
