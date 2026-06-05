#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/deployments/docker-compose.mock.otel.yml"

# shellcheck source=proof/preflight.sh
source "${SCRIPT_DIR}/preflight.sh"

ARTIFACT_DIR="${1:-${SCRIPT_DIR}/artifacts/mock_compose_otel/latest}"
GATEWAY_PORT="${GATEWAY_PORT:-18086}"
UPSTREAM_PORT="${UPSTREAM_PORT:-18087}"
JAEGER_PORT="${JAEGER_PORT:-16687}"
COLLECTOR_HEALTH_PORT="${COLLECTOR_HEALTH_PORT:-13134}"
GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:${GATEWAY_PORT}}"
JAEGER_URL="${JAEGER_URL:-http://127.0.0.1:${JAEGER_PORT}}"
COLLECTOR_HEALTH_URL="${COLLECTOR_HEALTH_URL:-http://127.0.0.1:${COLLECTOR_HEALTH_PORT}}"
OTEL_REQUEST_ID="${OTEL_REQUEST_ID:-otel-proof-request-1}"
OTEL_TRACE_ID="${OTEL_TRACE_ID:-otel-proof-trace-1}"
OTEL_GATEWAY_SERVICE_NAME="${OTEL_GATEWAY_SERVICE_NAME:-inference-serving-gateway}"

need_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

need_cmd docker
need_cmd curl
need_cmd python3

compose() {
  env \
    GATEWAY_PORT="${GATEWAY_PORT}" \
    UPSTREAM_PORT="${UPSTREAM_PORT}" \
    JAEGER_PORT="${JAEGER_PORT}" \
    COLLECTOR_HEALTH_PORT="${COLLECTOR_HEALTH_PORT}" \
    docker compose -f "${COMPOSE_FILE}" "$@"
}

cleanup() {
  if [[ "${KEEP_STACK:-0}" != "1" ]]; then
    compose down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_for_url() {
  local url="$1"
  local attempts="${2:-80}"
  for _ in $(seq 1 "${attempts}"); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  echo "Timed out waiting for ${url}" >&2
  return 1
}

capture_runtime() {
  local runtime_dir="${ARTIFACT_DIR}/runtime"
  mkdir -p "${runtime_dir}"
  compose ps >"${runtime_dir}/compose.ps.txt"
  compose images >"${runtime_dir}/compose.images.txt"
  compose logs gateway >"${runtime_dir}/gateway.container.log" 2>&1 || true
  compose logs mock-upstream >"${runtime_dir}/mock-upstream.container.log" 2>&1 || true
  compose logs otel-collector >"${runtime_dir}/otel-collector.container.log" 2>&1 || true
  compose logs jaeger >"${runtime_dir}/jaeger.container.log" 2>&1 || true
}

capture_get() {
  local name="$1"
  local url="$2"
  curl -fsS -D "${ARTIFACT_DIR}/${name}.headers" "${url}" >"${ARTIFACT_DIR}/${name}.body.json"
}

compose down --remove-orphans >/dev/null 2>&1 || true
require_ports_free "Mock Compose OTel proof" "${GATEWAY_PORT}" "${UPSTREAM_PORT}" "${JAEGER_PORT}" "${COLLECTOR_HEALTH_PORT}"

mkdir -p "${ARTIFACT_DIR}"
find "${ARTIFACT_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
compose up --build -d --force-recreate --remove-orphans

wait_for_url "${GATEWAY_URL}/healthz"
wait_for_url "${GATEWAY_URL}/readyz"
wait_for_url "${COLLECTOR_HEALTH_URL}"
wait_for_url "${JAEGER_URL}"

capture_get "healthz" "${GATEWAY_URL}/healthz"
capture_get "readyz" "${GATEWAY_URL}/readyz"
capture_get "collector_healthz" "${COLLECTOR_HEALTH_URL}"

EXTRACT_PAYLOAD='{"schema_id":"demo_schema_v1","text":"Vendor: ACME\nTotal: 10.00"}'
curl -fsS \
  -D "${ARTIFACT_DIR}/extract.headers" \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: ${OTEL_REQUEST_ID}" \
  -H "X-Trace-ID: ${OTEL_TRACE_ID}" \
  -d "${EXTRACT_PAYLOAD}" \
  "${GATEWAY_URL}/v1/extract" >"${ARTIFACT_DIR}/extract.body.json"

# Give the batch exporter time to send, then stop the gateway to force provider shutdown.
sleep 2
compose stop gateway >/dev/null
sleep 2

curl -fsS "${JAEGER_URL}/api/services" >"${ARTIFACT_DIR}/jaeger-services.json"
capture_runtime

ARTIFACT_DIR_ENV="${ARTIFACT_DIR}" \
JAEGER_URL_ENV="${JAEGER_URL}" \
OTEL_TRACE_ID_ENV="${OTEL_TRACE_ID}" \
OTEL_GATEWAY_SERVICE_NAME_ENV="${OTEL_GATEWAY_SERVICE_NAME}" \
python3 - <<'PY'
import json
import os
import time
import urllib.parse
import urllib.request
from pathlib import Path

artifact_dir = Path(os.environ["ARTIFACT_DIR_ENV"])
base_url = os.environ["JAEGER_URL_ENV"].rstrip("/")
trace_id = os.environ["OTEL_TRACE_ID_ENV"]
service_name = os.environ["OTEL_GATEWAY_SERVICE_NAME_ENV"]
query_start_us = int((time.time() - 300) * 1_000_000)
last_payload = {}

def trace_services(trace_payload):
    return {
        process.get("serviceName")
        for process in trace_payload.get("processes", {}).values()
        if process.get("serviceName")
    }

for _ in range(80):
    params = urllib.parse.urlencode(
        {
            "service": service_name,
            "limit": 20,
            "lookback": "custom",
            "start": query_start_us,
            "end": int(time.time_ns() // 1000),
            "tags": json.dumps({"llm.trace_id": trace_id}, sort_keys=True),
        }
    )
    with urllib.request.urlopen(f"{base_url}/api/traces?{params}") as response:
        payload = json.load(response)

    traces = payload.get("data", [])
    if traces:
        selected = traces[0]
        output = {
            "query_name": "mock_compose_otel_extract",
            "service": service_name,
            "tags": {"llm.trace_id": trace_id},
            "trace_count": len(traces),
            "selected_trace_id": selected.get("traceID"),
            "selected_trace_services": sorted(trace_services(selected)),
            "data": selected,
        }
        (artifact_dir / "extract_otel_trace.json").write_text(json.dumps(output, indent=2) + "\n")
        break
    last_payload = payload
    time.sleep(0.5)
else:
    output = {
        "query_name": "mock_compose_otel_extract",
        "service": service_name,
        "tags": {"llm.trace_id": trace_id},
        "error": "trace_not_found_before_timeout",
        "last_payload": last_payload,
    }
    (artifact_dir / "extract_otel_trace.json").write_text(json.dumps(output, indent=2) + "\n")
PY

ARTIFACT_DIR_ENV="${ARTIFACT_DIR}" \
GATEWAY_URL_ENV="${GATEWAY_URL}" \
JAEGER_URL_ENV="${JAEGER_URL}" \
COLLECTOR_HEALTH_URL_ENV="${COLLECTOR_HEALTH_URL}" \
OTEL_REQUEST_ID_ENV="${OTEL_REQUEST_ID}" \
OTEL_TRACE_ID_ENV="${OTEL_TRACE_ID}" \
OTEL_GATEWAY_SERVICE_NAME_ENV="${OTEL_GATEWAY_SERVICE_NAME}" \
python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

artifact_dir = Path(os.environ["ARTIFACT_DIR_ENV"])
request_id = os.environ["OTEL_REQUEST_ID_ENV"]
trace_id = os.environ["OTEL_TRACE_ID_ENV"]
service_name = os.environ["OTEL_GATEWAY_SERVICE_NAME_ENV"]

def read_json(name):
    return json.loads((artifact_dir / name).read_text())

def read_text(name):
    return (artifact_dir / name).read_text()

def header_map(name):
    out = {}
    for line in read_text(name).splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        out[key.strip().lower()] = value.strip()
    return out

def errorless_json(path):
    try:
        return read_json(path)
    except Exception:
        return None

def trace_span_names(trace_payload):
    data = trace_payload.get("data", {})
    return {span.get("operationName") for span in data.get("spans", []) if span.get("operationName")}

def trace_services(trace_payload):
    data = trace_payload.get("data", {})
    return {
        process.get("serviceName")
        for process in data.get("processes", {}).values()
        if process.get("serviceName")
    }

def trace_tags(trace_payload):
    tags = []
    data = trace_payload.get("data", {})
    for span in data.get("spans", []):
        tags.extend(span.get("tags", []))
    return tags

def trace_has_tag(trace_payload, key, value):
    return any(tag.get("key") == key and tag.get("value") == value for tag in trace_tags(trace_payload))

healthz = read_json("healthz.body.json")
readyz = read_json("readyz.body.json")
collector_healthz = read_json("collector_healthz.body.json")
extract = read_json("extract.body.json")
extract_headers = header_map("extract.headers")
services_payload = read_json("jaeger-services.json")
otel_trace = errorless_json("extract_otel_trace.json") or {}
collector_log = read_text("runtime/otel-collector.container.log")
gateway_log = read_text("runtime/gateway.container.log")
span_names = trace_span_names(otel_trace)
trace_services_seen = trace_services(otel_trace)

checks = {
    "healthz_ok": healthz == {"status": "ok"},
    "readyz_ready": readyz == {"status": "ready"},
    "collector_health_ok": collector_healthz.get("status") == "Server available",
    "extract_ok": extract.get("path") == "/v1/extract",
    "request_id_preserved": extract.get("request_id") == request_id and extract_headers.get("x-request-id") == request_id,
    "trace_id_preserved": extract.get("trace_id") == trace_id and extract_headers.get("x-trace-id") == trace_id,
    "traceparent_reached_mock_upstream": str(extract.get("traceparent", "")).startswith("00-"),
    "gateway_log_shows_otel_enabled": '"otel_enabled":true' in gateway_log,
    "collector_received_trace_data": "ResourceSpans" in collector_log or "resource spans" in collector_log.lower(),
    "jaeger_gateway_service_registered": service_name in services_payload.get("data", []),
    "jaeger_trace_found": bool(otel_trace.get("selected_trace_id")),
    "jaeger_trace_has_gateway_service": service_name in trace_services_seen,
    "jaeger_trace_contains_gateway_server_span": "gateway.extract" in span_names,
    "jaeger_trace_contains_upstream_client_span": "upstream.extract" in span_names,
    "jaeger_trace_has_request_id_attribute": trace_has_tag(otel_trace, "llm.request_id", request_id),
    "jaeger_trace_has_trace_id_attribute": trace_has_tag(otel_trace, "llm.trace_id", trace_id),
}

artifacts = {
    "healthz_body": "healthz.body.json",
    "readyz_body": "readyz.body.json",
    "collector_healthz_body": "collector_healthz.body.json",
    "extract_headers": "extract.headers",
    "extract_body": "extract.body.json",
    "jaeger_services": "jaeger-services.json",
    "extract_otel_trace": "extract_otel_trace.json",
    "compose_ps": "runtime/compose.ps.txt",
    "compose_images": "runtime/compose.images.txt",
    "gateway_container_log": "runtime/gateway.container.log",
    "mock_upstream_container_log": "runtime/mock-upstream.container.log",
    "otel_collector_container_log": "runtime/otel-collector.container.log",
    "jaeger_container_log": "runtime/jaeger.container.log",
}

manifest = {
    "mode": "mock_compose_otel",
    "gateway_url": os.environ["GATEWAY_URL_ENV"],
    "jaeger_url": os.environ["JAEGER_URL_ENV"],
    "collector_health_url": os.environ["COLLECTOR_HEALTH_URL_ENV"],
    "compose_file": "deployments/docker-compose.mock.otel.yml",
    "runtime_config": {
        "GATEWAY_OTEL_ENABLED": "true",
        "GATEWAY_OTEL_SERVICE_NAME": service_name,
        "GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT": "http://otel-collector:4318/v1/traces",
        "GATEWAY_UPSTREAM_BASE_URL": "http://mock-upstream:18081",
    },
    "checks": checks,
    "artifacts": artifacts,
    "expected_identity": {"request_id": request_id, "trace_id": trace_id},
    "expected_spans": ["gateway.extract", "upstream.extract"],
    "observed_span_names": sorted(name for name in span_names if name),
    "observed_services": sorted(trace_services_seen),
    "interpretation_limits": [
        "This proof validates isolated gateway OTLP/HTTP export and trace-context injection with a mock upstream.",
        "It does not validate backend inference semantics, worker traces, or Kubernetes observability wiring.",
    ],
}
(artifact_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

failed = [name for name, ok in checks.items() if not ok]
summary = [
    "# Mock Compose OTel Proof Summary",
    "",
    f"- Gateway URL: {os.environ['GATEWAY_URL_ENV']}",
    f"- Jaeger URL: {os.environ['JAEGER_URL_ENV']}",
    f"- Checks passed: {sum(1 for ok in checks.values() if ok)}",
    f"- Checks failed: {len(failed)}",
    "",
    "## Checks",
    "",
]
for name, ok in checks.items():
    summary.append(f"- {'pass' if ok else 'fail'}: `{name}`")
summary.extend(["", "## Failed Checks", ""])
if failed:
    summary.extend(f"- `{name}`" for name in failed)
else:
    summary.append("- none")
summary.append("")
(artifact_dir / "summary.md").write_text("\n".join(summary))

if failed:
    print("Mock Compose OTel proof validation failed:", file=sys.stderr)
    for name in failed:
        print(f" - {name}", file=sys.stderr)
    sys.exit(1)
PY

echo "Generated mock Compose OTel proof artifacts in ${ARTIFACT_DIR}"
