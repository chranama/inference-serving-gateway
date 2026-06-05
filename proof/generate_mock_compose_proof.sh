#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/deployments/docker-compose.mock.yml"

# shellcheck source=proof/preflight.sh
source "${SCRIPT_DIR}/preflight.sh"

ARTIFACT_DIR="${1:-${SCRIPT_DIR}/artifacts/mock_compose/latest}"
GATEWAY_PORT="${GATEWAY_PORT:-18080}"
UPSTREAM_PORT="${UPSTREAM_PORT:-18081}"
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"

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
  env GATEWAY_PORT="${GATEWAY_PORT}" UPSTREAM_PORT="${UPSTREAM_PORT}" docker compose -f "${COMPOSE_FILE}" "$@"
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
  local phase="$1"
  local runtime_dir="${ARTIFACT_DIR}/runtime/${phase}"
  mkdir -p "${runtime_dir}"
  compose ps >"${runtime_dir}/compose.ps.txt"
  compose images >"${runtime_dir}/compose.images.txt"
  compose logs gateway >"${runtime_dir}/gateway.container.log" 2>&1 || true
  compose logs mock-upstream >"${runtime_dir}/mock-upstream.container.log" 2>&1 || true
}

start_stack() {
  local phase="$1"
  shift

  env GATEWAY_PORT="${GATEWAY_PORT}" UPSTREAM_PORT="${UPSTREAM_PORT}" "$@" docker compose -f "${COMPOSE_FILE}" up --build -d --force-recreate --remove-orphans
  wait_for_url "${GATEWAY_URL}/healthz"
  wait_for_url "${GATEWAY_URL}/readyz"
  capture_runtime "${phase}"
}

run_probe() {
  local phase="$1"
  shift
  local phase_dir="${ARTIFACT_DIR}/${phase}"
  mkdir -p "${phase_dir}"

  local -a args=(
    python3 "${SCRIPT_DIR}/probe_mock_gateway.py"
    --artifact-dir "${phase_dir}"
    --gateway-url "${GATEWAY_URL}"
    --mode "mock_compose:${phase}"
  )
  local config_file="${ARTIFACT_DIR}/runtime/${phase}/runtime-config.env"
  if [[ -f "${config_file}" ]]; then
    local config_entry
    while IFS= read -r config_entry; do
      [[ -n "${config_entry}" ]] || continue
      args+=(--runtime-config "${config_entry}")
    done <"${config_file}"
  fi
  local scenario
  for scenario in "$@"; do
    args+=(--scenario "${scenario}")
  done
  "${args[@]}"
}

write_runtime_config() {
  local phase="$1"
  shift
  local runtime_dir="${ARTIFACT_DIR}/runtime/${phase}"
  mkdir -p "${runtime_dir}"
  : >"${runtime_dir}/runtime-config.env"
  local entry
  for entry in "$@"; do
    printf '%s\n' "${entry}" >>"${runtime_dir}/runtime-config.env"
  done
}

compose down --remove-orphans >/dev/null 2>&1 || true
require_ports_free "Mock Compose proof" "${GATEWAY_PORT}" "${UPSTREAM_PORT}"

mkdir -p "${ARTIFACT_DIR}"
find "${ARTIFACT_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

start_stack \
  base \
  GATEWAY_REQUEST_TIMEOUT=2s \
  GATEWAY_CONCURRENCY_LIMIT=1 \
  GATEWAY_RATE_LIMIT_PER_SECOND=0
write_runtime_config \
  base \
  GATEWAY_REQUEST_TIMEOUT=2s \
  GATEWAY_CONCURRENCY_LIMIT=1 \
  GATEWAY_RATE_LIMIT_PER_SECOND=0
run_probe base base concurrency unsupported_route

compose stop mock-upstream >/dev/null
sleep 0.5
write_runtime_config upstream_unavailable GATEWAY_UPSTREAM_BASE_URL=http://mock-upstream:18081
capture_runtime upstream_unavailable
run_probe upstream_unavailable upstream_unavailable

start_stack timeout GATEWAY_REQUEST_TIMEOUT=100ms
write_runtime_config timeout GATEWAY_REQUEST_TIMEOUT=100ms
run_probe timeout timeout

start_stack request_too_large GATEWAY_MAX_BODY_BYTES=4
write_runtime_config request_too_large GATEWAY_MAX_BODY_BYTES=4
run_probe request_too_large request_too_large

start_stack route_disabled GATEWAY_ALLOW_EXTRACT=false
write_runtime_config route_disabled GATEWAY_ALLOW_EXTRACT=false
run_probe route_disabled route_disabled

start_stack extract_jobs_disabled GATEWAY_ALLOW_EXTRACT_JOBS=false
write_runtime_config extract_jobs_disabled GATEWAY_ALLOW_EXTRACT_JOBS=false
run_probe extract_jobs_disabled extract_jobs_disabled

start_stack job_status_disabled GATEWAY_ALLOW_JOB_STATUS=false
write_runtime_config job_status_disabled GATEWAY_ALLOW_JOB_STATUS=false
run_probe job_status_disabled job_status_disabled

start_stack metrics_disabled GATEWAY_ENABLE_METRICS=false
write_runtime_config metrics_disabled GATEWAY_ENABLE_METRICS=false
run_probe metrics_disabled metrics_disabled

start_stack \
  rate_limit \
  GATEWAY_RATE_LIMIT_PER_SECOND=0.01 \
  GATEWAY_RATE_LIMIT_BURST=1
write_runtime_config \
  rate_limit \
  GATEWAY_RATE_LIMIT_PER_SECOND=0.01 \
  GATEWAY_RATE_LIMIT_BURST=1
run_probe rate_limit rate_limit

capture_runtime final

ARTIFACT_DIR_ENV="${ARTIFACT_DIR}" GATEWAY_URL_ENV="${GATEWAY_URL}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

artifact_dir = Path(os.environ["ARTIFACT_DIR_ENV"])
phases = [
    "base",
    "upstream_unavailable",
    "timeout",
    "request_too_large",
    "route_disabled",
    "extract_jobs_disabled",
    "job_status_disabled",
    "metrics_disabled",
    "rate_limit",
]

phase_manifests = {}
runtime_config = {}
checks = {}
artifacts = {}
for phase in phases:
    manifest_path = artifact_dir / phase / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    phase_manifests[phase] = str(manifest_path.relative_to(artifact_dir))
    runtime_config[phase] = manifest.get("runtime_config", {})
    for name, ok in manifest["checks"].items():
        checks[f"{phase}.{name}"] = ok
    artifacts[f"{phase}_manifest"] = str(manifest_path.relative_to(artifact_dir))
    artifacts[f"{phase}_summary"] = f"{phase}/summary.md"

runtime_root = artifact_dir / "runtime"
for path in sorted(runtime_root.glob("*/*")):
    artifacts[f"runtime_{path.parent.name}_{path.name.replace('.', '_')}"] = str(path.relative_to(artifact_dir))

manifest = {
    "mode": "mock_compose",
    "gateway_url": os.environ["GATEWAY_URL_ENV"],
    "compose_file": "deployments/docker-compose.mock.yml",
    "phase_manifests": phase_manifests,
    "runtime_config": runtime_config,
    "checks": checks,
    "artifacts": artifacts,
    "interpretation_limits": [
        "This manifest validates the Docker Compose mock deployment and gateway-owned edge behavior.",
        "It does not validate a real inference backend or production operations.",
    ],
}
(artifact_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

failed = [name for name, ok in checks.items() if not ok]
summary = [
    "# Mock Compose Proof Summary",
    "",
    f"- Gateway URL: {os.environ['GATEWAY_URL_ENV']}",
    f"- Phases: {', '.join(phases)}",
    f"- Checks passed: {sum(1 for ok in checks.values() if ok)}",
    f"- Checks failed: {len(failed)}",
    "",
    "## Phase Manifests",
    "",
]
for phase in phases:
    summary.append(f"- `{phase}/manifest.json`")
summary.extend(["", "## Failed Checks", ""])
if failed:
    summary.extend(f"- `{name}`" for name in failed)
else:
    summary.append("- none")
summary.append("")
(artifact_dir / "summary.md").write_text("\n".join(summary))

if failed:
    print("Mock Compose proof validation failed:", file=sys.stderr)
    for name in failed:
        print(f" - {name}", file=sys.stderr)
    sys.exit(1)
PY

echo "Generated mock Compose proof artifacts in ${ARTIFACT_DIR}"
