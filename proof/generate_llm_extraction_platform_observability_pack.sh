#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${LLM_EXTRACTION_PLATFORM_BASE_URL:-}" ]]; then
  echo "Set LLM_EXTRACTION_PLATFORM_BASE_URL before running this script." >&2
  exit 1
fi

if [[ -z "${LLM_EXTRACTION_PLATFORM_API_KEY:-}" ]]; then
  echo "Set LLM_EXTRACTION_PLATFORM_API_KEY before running this script." >&2
  exit 1
fi

if [[ -z "${LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY:-}" ]]; then
  echo "Set LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY before running this script." >&2
  exit 1
fi

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

require_command python3
require_command curl

ARTIFACT_DIR="${1:-${SCRIPT_DIR}/artifacts/llm_extraction_platform/observability_latest}"
GATEWAY_PORT="${GATEWAY_PORT:-18082}"
GATEWAY_BASE_URL="${GATEWAY_BASE_URL:-}"
GATEWAY_LOG_PATH="${GATEWAY_LOG_PATH:-}"
BACKEND_URL="${LLM_EXTRACTION_PLATFORM_BASE_URL%/}"
POLL_ATTEMPTS="${POLL_ATTEMPTS:-80}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-0.25}"
JAEGER_BASE_URL="${JAEGER_BASE_URL:-}"
OTEL_GATEWAY_SERVICE_NAME="${OTEL_GATEWAY_SERVICE_NAME:-inference-serving-gateway}"
OTEL_BACKEND_SERVICE_NAME="${OTEL_BACKEND_SERVICE_NAME:-llm-extraction-platform}"
OTEL_WORKER_SERVICE_NAME="${OTEL_WORKER_SERVICE_NAME:-llm-extraction-platform-worker}"

SYNC_REQUEST_ID="${SYNC_REQUEST_ID:-integration-obs-request-1}"
SYNC_TRACE_ID="${SYNC_TRACE_ID:-integration-obs-trace-1}"
ASYNC_SUBMIT_REQUEST_ID="${ASYNC_SUBMIT_REQUEST_ID:-integration-obs-request-2}"
ASYNC_TRACE_ID="${ASYNC_TRACE_ID:-integration-obs-trace-2}"
ASYNC_POLL_REQUEST_ID="${ASYNC_POLL_REQUEST_ID:-integration-obs-request-3}"
OBS_SCHEMA_ID="${OBS_SCHEMA_ID:-sroie_receipt_v1}"
OBS_TEXT="${OBS_TEXT:-Vendor: ACME\nTotal: 10.00}"
PROOF_STARTED_AT_US="$(python3 - <<'PY'
import time

print(time.time_ns() // 1000)
PY
)"

mkdir -p "${ARTIFACT_DIR}"
rm -f "${ARTIFACT_DIR}"/*

cleanup() {
  if [[ -n "${GATEWAY_PID:-}" ]]; then
    kill "${GATEWAY_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ -n "${GATEWAY_BASE_URL}" ]]; then
  GATEWAY_URL="${GATEWAY_BASE_URL%/}"
else
  require_command go
  GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"
  (
    cd "${REPO_ROOT}"
    GATEWAY_LISTEN_ADDR="127.0.0.1:${GATEWAY_PORT}" \
    GATEWAY_UPSTREAM_BASE_URL="${BACKEND_URL}" \
    GATEWAY_OTEL_ENABLED="${GATEWAY_OTEL_ENABLED:-0}" \
    GATEWAY_OTEL_SERVICE_NAME="${OTEL_GATEWAY_SERVICE_NAME}" \
    GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT="${GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT:-}" \
    go run ./cmd/gateway >"${ARTIFACT_DIR}/gateway.log" 2>&1
  ) &
  GATEWAY_PID=$!
fi

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

wait_for_url "${BACKEND_URL}/healthz"
wait_for_url "${GATEWAY_URL}/healthz"

EXTRACT_PAYLOAD="$(
  OBS_SCHEMA_ID_ENV="${OBS_SCHEMA_ID}" OBS_TEXT_ENV="${OBS_TEXT}" python3 - <<'PY'
import json
import os

payload = {
    "schema_id": os.environ["OBS_SCHEMA_ID_ENV"],
    "text": os.environ["OBS_TEXT_ENV"],
    "cache": False,
    "repair": True,
}
print(json.dumps(payload))
PY
)"

curl -fsS \
  -D "${ARTIFACT_DIR}/extract.headers" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_API_KEY}" \
  -H "X-Request-ID: ${SYNC_REQUEST_ID}" \
  -H "X-Trace-ID: ${SYNC_TRACE_ID}" \
  -d "${EXTRACT_PAYLOAD}" \
  "${GATEWAY_URL}/v1/extract" >"${ARTIFACT_DIR}/extract.body.json"

SYNC_BACKEND_TRACE_ID="$(
  python3 - <<'PY' "${ARTIFACT_DIR}/extract.headers"
import sys
from pathlib import Path

for line in Path(sys.argv[1]).read_text().splitlines():
    if ":" not in line:
        continue
    key, value = line.split(":", 1)
    if key.strip().lower() == "x-trace-id":
        print(value.strip())
        break
PY
)"

if [[ "${SYNC_BACKEND_TRACE_ID}" != "${SYNC_TRACE_ID}" ]]; then
  echo "Backend did not preserve the injected sync trace ID." >&2
  echo "Expected: ${SYNC_TRACE_ID}" >&2
  echo "Observed: ${SYNC_BACKEND_TRACE_ID:-<missing>}" >&2
  echo "Start the backend with EDGE_MODE=behind_gateway so it trusts gateway trace headers." >&2
  exit 1
fi

curl -fsS \
  -D "${ARTIFACT_DIR}/extract_jobs.headers" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_API_KEY}" \
  -H "X-Request-ID: ${ASYNC_SUBMIT_REQUEST_ID}" \
  -H "X-Trace-ID: ${ASYNC_TRACE_ID}" \
  -d "${EXTRACT_PAYLOAD}" \
  "${GATEWAY_URL}/v1/extract/jobs" >"${ARTIFACT_DIR}/extract_jobs.body.json"

JOB_ID="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["job_id"])' \
    "${ARTIFACT_DIR}/extract_jobs.body.json"
)"

ASYNC_BACKEND_TRACE_ID="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["trace_id"])' \
    "${ARTIFACT_DIR}/extract_jobs.body.json"
)"

if [[ "${ASYNC_BACKEND_TRACE_ID}" != "${ASYNC_TRACE_ID}" ]]; then
  echo "Backend did not preserve the injected async trace ID on submit." >&2
  echo "Expected: ${ASYNC_TRACE_ID}" >&2
  echo "Observed: ${ASYNC_BACKEND_TRACE_ID:-<missing>}" >&2
  echo "Start the backend with EDGE_MODE=behind_gateway so it trusts gateway trace headers." >&2
  exit 1
fi

FINAL_STATUS=""
TMP_STATUS_HEADERS="${ARTIFACT_DIR}/job_status.tmp.headers"
TMP_STATUS_BODY="${ARTIFACT_DIR}/job_status.tmp.body.json"

for _ in $(seq 1 "${POLL_ATTEMPTS}"); do
  curl -fsS \
    -D "${TMP_STATUS_HEADERS}" \
    -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_API_KEY}" \
    -H "X-Request-ID: ${ASYNC_POLL_REQUEST_ID}" \
    -H "X-Trace-ID: ${ASYNC_TRACE_ID}" \
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

ASYNC_POLL_TRACE_ID="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("trace_id",""))' \
    "${ARTIFACT_DIR}/job_status.body.json"
)"

if [[ "${ASYNC_POLL_TRACE_ID}" != "${ASYNC_TRACE_ID}" ]]; then
  echo "Backend did not preserve the injected async trace ID on poll." >&2
  echo "Expected: ${ASYNC_TRACE_ID}" >&2
  echo "Observed: ${ASYNC_POLL_TRACE_ID:-<missing>}" >&2
  echo "Start the backend with EDGE_MODE=behind_gateway so it trusts gateway trace headers." >&2
  exit 1
fi

curl -fsS "${GATEWAY_URL}/metrics" >"${ARTIFACT_DIR}/gateway.metrics.txt"
curl -fsS "${BACKEND_URL}/metrics" >"${ARTIFACT_DIR}/backend.metrics.txt"

curl -fsS \
  -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY}" \
  "${BACKEND_URL}/v1/admin/traces/${SYNC_TRACE_ID}" >"${ARTIFACT_DIR}/sync_trace_detail.json"

curl -fsS \
  -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY}" \
  "${BACKEND_URL}/v1/admin/traces/${ASYNC_TRACE_ID}" >"${ARTIFACT_DIR}/async_trace_detail.json"

curl -fsS \
  -G \
  -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY}" \
  --data-urlencode "trace_id=${SYNC_TRACE_ID}" \
  "${BACKEND_URL}/v1/admin/logs" >"${ARTIFACT_DIR}/sync_logs.json"

curl -fsS \
  -G \
  -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY}" \
  --data-urlencode "trace_id=${ASYNC_TRACE_ID}" \
  --data-urlencode "job_id=${JOB_ID}" \
  "${BACKEND_URL}/v1/admin/logs" >"${ARTIFACT_DIR}/async_logs.json"

curl -fsS \
  -G \
  -H "X-API-Key: ${LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY}" \
  --data-urlencode "request_id=${ASYNC_POLL_REQUEST_ID}" \
  "${BACKEND_URL}/v1/admin/logs" >"${ARTIFACT_DIR}/async_poll_logs.json"

if [[ -n "${GATEWAY_LOG_PATH}" && -f "${GATEWAY_LOG_PATH}" ]]; then
  cp "${GATEWAY_LOG_PATH}" "${ARTIFACT_DIR}/gateway.log"
fi

if [[ -n "${JAEGER_BASE_URL}" ]]; then
  ARTIFACT_DIR_ENV="${ARTIFACT_DIR}" \
  JAEGER_BASE_URL_ENV="${JAEGER_BASE_URL%/}" \
  OTEL_GATEWAY_SERVICE_NAME_ENV="${OTEL_GATEWAY_SERVICE_NAME}" \
  OTEL_BACKEND_SERVICE_NAME_ENV="${OTEL_BACKEND_SERVICE_NAME}" \
  OTEL_WORKER_SERVICE_NAME_ENV="${OTEL_WORKER_SERVICE_NAME}" \
  SYNC_TRACE_ID_ENV="${SYNC_TRACE_ID}" \
  ASYNC_TRACE_ID_ENV="${ASYNC_TRACE_ID}" \
  ASYNC_JOB_ID_ENV="${JOB_ID}" \
  PROOF_STARTED_AT_US_ENV="${PROOF_STARTED_AT_US}" \
  python3 - <<'PY'
import json
import os
import time
import urllib.parse
import urllib.request
from pathlib import Path

artifact_dir = Path(os.environ["ARTIFACT_DIR_ENV"])
base_url = os.environ["JAEGER_BASE_URL_ENV"]
proof_started_at_us = int(os.environ["PROOF_STARTED_AT_US_ENV"])


def fetch_trace(query_name: str, service: str, tags: dict[str, str], output_name: str) -> None:
    last_payload = None
    query_start_us = max(proof_started_at_us - 5_000_000, 0)

    for _ in range(80):
        params = urllib.parse.urlencode(
            {
                "service": service,
                "limit": 20,
                "lookback": "custom",
                "start": query_start_us,
                "end": int(time.time_ns() // 1000),
                "tags": json.dumps(tags, sort_keys=True),
            }
        )
        with urllib.request.urlopen(f"{base_url}/api/traces?{params}") as response:
            payload = json.load(response)
        traces = payload.get("data", [])
        if traces:
            selected = traces[0]
            output = {
                "query_name": query_name,
                "service": service,
                "tags": tags,
                "trace_count": len(traces),
                "selected_trace_id": selected.get("traceID"),
                "data": selected,
            }
            (artifact_dir / output_name).write_text(json.dumps(output, indent=2) + "\n")
            return
        last_payload = payload
        time.sleep(0.5)

    failure = {
        "query_name": query_name,
        "service": service,
        "tags": tags,
        "error": "trace_not_found_before_timeout",
        "last_payload": last_payload,
    }
    (artifact_dir / output_name).write_text(json.dumps(failure, indent=2) + "\n")
    raise SystemExit(f"Timed out waiting for Jaeger trace export for {query_name}.")


fetch_trace(
    query_name="sync",
    service=os.environ["OTEL_GATEWAY_SERVICE_NAME_ENV"],
    tags={"llm.trace_id": os.environ["SYNC_TRACE_ID_ENV"]},
    output_name="sync_otel_trace.json",
)
fetch_trace(
    query_name="async",
    service=os.environ["OTEL_WORKER_SERVICE_NAME_ENV"],
    tags={
        "llm.trace_id": os.environ["ASYNC_TRACE_ID_ENV"],
        "llm.job_id": os.environ["ASYNC_JOB_ID_ENV"],
    },
    output_name="async_otel_trace.json",
)
PY
fi

ARTIFACT_DIR_ENV="${ARTIFACT_DIR}" \
SYNC_REQUEST_ID_ENV="${SYNC_REQUEST_ID}" \
SYNC_TRACE_ID_ENV="${SYNC_TRACE_ID}" \
ASYNC_SUBMIT_REQUEST_ID_ENV="${ASYNC_SUBMIT_REQUEST_ID}" \
ASYNC_TRACE_ID_ENV="${ASYNC_TRACE_ID}" \
ASYNC_POLL_REQUEST_ID_ENV="${ASYNC_POLL_REQUEST_ID}" \
OTEL_GATEWAY_SERVICE_NAME_ENV="${OTEL_GATEWAY_SERVICE_NAME}" \
OTEL_BACKEND_SERVICE_NAME_ENV="${OTEL_BACKEND_SERVICE_NAME}" \
OTEL_WORKER_SERVICE_NAME_ENV="${OTEL_WORKER_SERVICE_NAME}" \
python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

artifact_dir = Path(os.environ["ARTIFACT_DIR_ENV"])
sync_request_id = os.environ["SYNC_REQUEST_ID_ENV"]
sync_trace_id = os.environ["SYNC_TRACE_ID_ENV"]
async_submit_request_id = os.environ["ASYNC_SUBMIT_REQUEST_ID_ENV"]
async_trace_id = os.environ["ASYNC_TRACE_ID_ENV"]
async_poll_request_id = os.environ["ASYNC_POLL_REQUEST_ID_ENV"]
otel_gateway_service_name = os.environ["OTEL_GATEWAY_SERVICE_NAME_ENV"]
otel_backend_service_name = os.environ["OTEL_BACKEND_SERVICE_NAME_ENV"]
otel_worker_service_name = os.environ["OTEL_WORKER_SERVICE_NAME_ENV"]

def read_json(name: str):
    return json.loads((artifact_dir / name).read_text())

def read_text(name: str):
    return (artifact_dir / name).read_text()

def read_json_if_exists(name: str):
    path = artifact_dir / name
    if not path.exists():
        return None
    return json.loads(path.read_text())

def header_map(name: str):
    out = {}
    for line in read_text(name).splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        out[key.strip().lower()] = value.strip()
    return out

extract_headers = header_map("extract.headers")
extract_jobs_headers = header_map("extract_jobs.headers")
job_status_headers = header_map("job_status.headers")

extract = read_json("extract.body.json")
extract_jobs = read_json("extract_jobs.body.json")
job_status = read_json("job_status.body.json")
sync_trace = read_json("sync_trace_detail.json")
async_trace = read_json("async_trace_detail.json")
sync_logs = read_json("sync_logs.json")
async_logs = read_json("async_logs.json")
async_poll_logs = read_json("async_poll_logs.json")
sync_otel_trace = read_json_if_exists("sync_otel_trace.json")
async_otel_trace = read_json_if_exists("async_otel_trace.json")
gateway_metrics = read_text("gateway.metrics.txt")
backend_metrics = read_text("backend.metrics.txt")
gateway_log_present = (artifact_dir / "gateway.log").exists()

sync_event_names = [item.get("event_name") for item in sync_trace.get("events", [])]
async_event_names = [item.get("event_name") for item in async_trace.get("events", [])]
sync_log_items = sync_logs.get("items", [])
async_log_items = async_logs.get("items", [])
async_job_id = extract_jobs.get("job_id")

def jaeger_services(trace_payload):
    if not trace_payload or "data" not in trace_payload:
        return set()
    processes = trace_payload["data"].get("processes", {})
    return {
        process.get("serviceName")
        for process in processes.values()
        if process.get("serviceName")
    }

sync_otel_services = sorted(jaeger_services(sync_otel_trace))
async_otel_services = sorted(jaeger_services(async_otel_trace))

checks = {
    "sync_request_id_preserved": extract_headers.get("x-request-id") == sync_request_id,
    "async_submit_request_id_preserved": extract_jobs_headers.get("x-request-id") == async_submit_request_id,
    "async_poll_request_id_preserved": job_status_headers.get("x-request-id") == async_poll_request_id,
    "sync_response_trace_id_preserved": extract_headers.get("x-trace-id") == sync_trace_id,
    "async_submit_response_trace_id_preserved": extract_jobs_headers.get("x-trace-id") == async_trace_id,
    "async_submit_body_trace_id_preserved": extract_jobs.get("trace_id") == async_trace_id,
    "async_poll_response_trace_id_preserved": job_status_headers.get("x-trace-id") == async_trace_id,
    "async_poll_body_trace_id_preserved": job_status.get("trace_id") == async_trace_id,
    "sync_trace_detail_present": sync_trace.get("trace_id") == sync_trace_id,
    "async_trace_detail_present": async_trace.get("trace_id") == async_trace_id,
    "sync_trace_has_completion": "extract.completed" in sync_event_names,
    "async_trace_has_worker_claim": "extract_job.worker_claimed" in async_event_names,
    "async_trace_has_status_poll": "extract_job.status_polled" in async_event_names,
    "async_trace_has_completion": "extract_job.completed" in async_event_names,
    "sync_execution_logs_present": int(sync_logs.get("total", 0)) >= 1,
    "sync_execution_logs_match_trace_id": any(
        item.get("trace_id") == sync_trace_id and item.get("route") == "/v1/extract"
        for item in sync_log_items
    ),
    "async_execution_logs_present": int(async_logs.get("total", 0)) >= 1,
    "async_execution_logs_match_trace_and_job_id": any(
        item.get("trace_id") == async_trace_id
        and item.get("job_id") == async_job_id
        and item.get("route") == "/v1/extract/jobs/worker"
        for item in async_log_items
    ),
    "gateway_metrics_include_requests_total": "gateway_requests_total" in gateway_metrics,
    "gateway_metrics_include_upstream_total": "gateway_upstream_requests_total" in gateway_metrics,
    "backend_metrics_include_api_requests_total": "llm_api_request_total" in backend_metrics,
    "backend_metrics_include_extraction_requests_total": "llm_extraction_requests_total" in backend_metrics,
}

if sync_otel_trace is not None or async_otel_trace is not None:
    checks.update(
        {
            "sync_otel_trace_present": bool(sync_otel_trace and sync_otel_trace.get("selected_trace_id")),
            "sync_otel_trace_has_gateway_service": otel_gateway_service_name in sync_otel_services,
            "sync_otel_trace_has_backend_service": otel_backend_service_name in sync_otel_services,
            "async_otel_trace_present": bool(async_otel_trace and async_otel_trace.get("selected_trace_id")),
            "async_otel_trace_has_gateway_service": otel_gateway_service_name in async_otel_services,
            "async_otel_trace_has_backend_service": otel_backend_service_name in async_otel_services,
            "async_otel_trace_has_worker_service": otel_worker_service_name in async_otel_services,
        }
    )

failed = [name for name, ok in checks.items() if not ok]

artifacts = {
    "gateway_metrics": "gateway.metrics.txt",
    "backend_metrics": "backend.metrics.txt",
    "sync_extract_headers": "extract.headers",
    "sync_extract_body": "extract.body.json",
    "async_submit_headers": "extract_jobs.headers",
    "async_submit_body": "extract_jobs.body.json",
    "async_status_headers": "job_status.headers",
    "async_status_body": "job_status.body.json",
    "sync_trace_detail": "sync_trace_detail.json",
    "async_trace_detail": "async_trace_detail.json",
    "sync_logs": "sync_logs.json",
    "async_logs": "async_logs.json",
    "async_poll_logs": "async_poll_logs.json",
}
if gateway_log_present:
    artifacts["gateway_log"] = "gateway.log"
if sync_otel_trace is not None:
    artifacts["sync_otel_trace"] = "sync_otel_trace.json"
if async_otel_trace is not None:
    artifacts["async_otel_trace"] = "async_otel_trace.json"

manifest = {
    "mode": "llm_extraction_platform_observability_pack",
    "checks": checks,
    "ids": {
        "sync_request_id": sync_request_id,
        "async_submit_request_id": async_submit_request_id,
        "async_poll_request_id": async_poll_request_id,
        "async_job_id": async_job_id,
    },
    "artifacts": artifacts,
    "expected_trace_ids": {
        "sync": sync_trace_id,
        "async": async_trace_id,
    },
    "observed_response_trace_ids": {
        "sync_header": extract_headers.get("x-trace-id"),
        "async_submit_header": extract_jobs_headers.get("x-trace-id"),
        "async_submit_body": extract_jobs.get("trace_id"),
        "async_poll_header": job_status_headers.get("x-trace-id"),
        "async_poll_body": job_status.get("trace_id"),
    },
    "execution_log_query_contract": {
        "sync_logs": {"trace_id": sync_trace_id},
        "async_logs": {"trace_id": async_trace_id, "job_id": async_job_id},
        "async_poll_logs": {
            "request_id": async_poll_request_id,
            "expectation": "observation_only_may_be_empty",
        },
    },
    "surface_semantics": {
        "admin_logs": "inference_execution_only",
        "poll_request_visibility": [
            "gateway access logs",
            "backend access logs",
            "backend trace events",
        ],
        "poll_request_not_required_in": ["/v1/admin/logs"],
    },
    "otel_semantics": {
        "enabled": sync_otel_trace is not None or async_otel_trace is not None,
        "application_trace_id_role": "logical_operation_identity",
        "otel_trace_id_role": "transport_level_distributed_trace_identity",
        "span_attributes": ["llm.request_id", "llm.trace_id", "llm.job_id"],
        "async_poll_model": "separate_request_traces_with_shared_application_trace_and_job_identity",
        "sync_services": sync_otel_services,
        "async_services": async_otel_services,
    },
    "observations": {
        "async_poll_log_total": int(async_poll_logs.get("total", 0)),
    },
    "sync_event_names": sync_event_names,
    "async_event_names": async_event_names,
}

(artifact_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

captured_surfaces = []
if gateway_log_present:
    captured_surfaces.append("- `gateway.log`")
captured_surfaces.extend(
    [
        "- `gateway.metrics.txt`",
        "- `backend.metrics.txt`",
        "- `sync_trace_detail.json`",
        "- `async_trace_detail.json`",
    ]
)
if sync_otel_trace is not None:
    captured_surfaces.append("- `sync_otel_trace.json`")
if async_otel_trace is not None:
    captured_surfaces.append("- `async_otel_trace.json`")
captured_surfaces.extend(
    [
        "- `sync_logs.json`",
        "- `async_logs.json`",
        "- `async_poll_logs.json`",
        "- `manifest.json`",
    ]
)

summary_lines = [
    "# Integrated Observability Pack",
    "",
    f"- Sync request ID: `{sync_request_id}`",
    f"- Shared sync trace ID: `{sync_trace_id}`",
    f"- Async submit request ID: `{async_submit_request_id}`",
    f"- Shared async trace ID: `{async_trace_id}`",
    f"- Async poll request ID: `{async_poll_request_id}`",
    f"- Async job ID: `{extract_jobs.get('job_id')}`",
    "",
    "Captured surfaces:",
    "",
    *captured_surfaces,
    "",
    "Surface semantics:",
    "",
    "- `sync_logs.json` is an execution-log slice queried by shared sync `trace_id`",
    "- `async_logs.json` is an execution-log slice queried by shared async `trace_id` plus `job_id`",
    "- `async_poll_logs.json` is an observation artifact keyed by poll `request_id` and may be empty because polls are not inference executions",
    "",
    "What this pack proves:",
    "",
    "- request IDs are preserved across gateway and backend surfaces",
    "- shared trace IDs are preserved from gateway injection through backend response and admin trace inspection",
    "- sync extract execution rows are directly joinable by shared `trace_id`",
    "- async worker execution rows are directly joinable by shared `trace_id` and `job_id`",
    "- async extract is inspectable through submit, worker, and poll trace events",
    "- both gateway and backend metrics can be checked from one run",
]

if sync_otel_trace is not None or async_otel_trace is not None:
    summary_lines.extend(
        [
            "",
            "OpenTelemetry note:",
            "",
            "- `sync_otel_trace.json` is a Jaeger export for the sync distributed trace",
            "- `async_otel_trace.json` is a Jaeger export for the async submit plus worker continuation trace",
            "- poll requests remain separate HTTP request traces and are not folded into `async_otel_trace.json`",
            "- application `trace_id` remains the logical-operation ID; OTel `TraceId` is a separate transport-level trace identifier",
        ]
    )

(artifact_dir / "summary.md").write_text("\n".join(summary_lines) + "\n")

if failed:
    print("Integrated observability pack validation failed:")
    for name in failed:
        print(f" - {name}")
    sys.exit(1)
PY

echo "Generated integrated observability artifacts in ${ARTIFACT_DIR}"
