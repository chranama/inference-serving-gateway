#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUSTOMIZATION="${REPO_ROOT}/deploy/k8s/mock-kind"
ARTIFACT_DIR="${SCRIPT_DIR}/artifacts/mock_kind/latest"

# shellcheck source=proof/preflight.sh
source "${SCRIPT_DIR}/preflight.sh"

: "${MOCK_KIND_CLUSTER:=inference-gateway}"
: "${MOCK_KIND_NAMESPACE:=inference-gateway-mock}"
: "${MOCK_KIND_GATEWAY_LOCAL_PORT:=18085}"
: "${MOCK_KIND_GATEWAY_IMAGE:=inference-serving-gateway:mock-kind}"
: "${MOCK_KIND_UPSTREAM_IMAGE:=inference-gateway-mock-upstream:dev}"

usage() {
  cat <<'EOF'
Usage:
  proof/run_mock_kind_stack.sh up
  proof/run_mock_kind_stack.sh status
  proof/run_mock_kind_stack.sh proof
  proof/run_mock_kind_stack.sh down

This is the gateway-isolated Kubernetes artifact workflow. It runs only the gateway
and deterministic mock upstream in a local kind cluster.
EOF
}

need_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

ensure_docker_ready() {
  if ! docker info >/dev/null 2>&1; then
    echo "Docker is required for the mock kind stack, but the Docker daemon is not reachable." >&2
    exit 1
  fi
}

kubectl_base() {
  kubectl --context "kind-${MOCK_KIND_CLUSTER}" "$@"
}

kubectl_ns() {
  kubectl_base -n "${MOCK_KIND_NAMESPACE}" "$@"
}

ensure_kind_cluster() {
  if kind get clusters | grep -qx "${MOCK_KIND_CLUSTER}"; then
    return 0
  fi
  kind create cluster --name "${MOCK_KIND_CLUSTER}"
}

build_and_load_images() {
  docker build \
    -t "${MOCK_KIND_GATEWAY_IMAGE}" \
    -f "${REPO_ROOT}/Dockerfile" \
    "${REPO_ROOT}"
  kind load docker-image "${MOCK_KIND_GATEWAY_IMAGE}" --name "${MOCK_KIND_CLUSTER}"

  docker build \
    -t "${MOCK_KIND_UPSTREAM_IMAGE}" \
    -f "${REPO_ROOT}/proof/mock_upstream.Dockerfile" \
    "${REPO_ROOT}"
  kind load docker-image "${MOCK_KIND_UPSTREAM_IMAGE}" --name "${MOCK_KIND_CLUSTER}"
}

wait_for_deployment() {
  local name="$1"
  kubectl_ns rollout status "deployment/${name}" --timeout=180s
}

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

start_gateway_port_forward() {
  local log_path="$1"
  : >"${log_path}"
  kubectl_ns port-forward "svc/gateway" "${MOCK_KIND_GATEWAY_LOCAL_PORT}:8080" >"${log_path}" 2>&1 &
  echo $!
}

capture_k8s_state() {
  local phase="$1"
  local runtime_dir="${ARTIFACT_DIR}/runtime/${phase}"
  mkdir -p "${runtime_dir}"

  kubectl_ns get pods -o wide >"${runtime_dir}/pods.txt"
  kubectl_ns get deploy -o wide >"${runtime_dir}/deployments.txt"
  kubectl_ns get svc -o wide >"${runtime_dir}/services.txt"
  kubectl_ns describe deploy gateway >"${runtime_dir}/gateway.deployment.describe.txt" || true
  kubectl_ns describe deploy mock-upstream >"${runtime_dir}/mock-upstream.deployment.describe.txt" || true
  kubectl_ns logs deployment/gateway --all-containers --tail=200 >"${runtime_dir}/gateway.container.log" 2>&1 || true
  kubectl_ns logs deployment/mock-upstream --all-containers --tail=200 >"${runtime_dir}/mock-upstream.container.log" 2>&1 || true
}

run_probe() {
  local phase="$1"
  shift
  local phase_dir="${ARTIFACT_DIR}/${phase}"
  mkdir -p "${phase_dir}"

  local -a args=(
    python3 "${SCRIPT_DIR}/probe_mock_gateway.py"
    --artifact-dir "${phase_dir}"
    --gateway-url "http://127.0.0.1:${MOCK_KIND_GATEWAY_LOCAL_PORT}"
    --mode "mock_kind:${phase}"
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

cmd_up() {
  need_cmd docker
  need_cmd kind
  need_cmd kubectl
  ensure_docker_ready

  ensure_kind_cluster
  build_and_load_images
  kubectl_base apply -k "${KUSTOMIZATION}"
  wait_for_deployment mock-upstream
  wait_for_deployment gateway

  echo "Mock kind stack is up."
  echo "Cluster: ${MOCK_KIND_CLUSTER}"
  echo "Namespace: ${MOCK_KIND_NAMESPACE}"
}

cmd_down() {
  if kind get clusters | grep -qx "${MOCK_KIND_CLUSTER}"; then
    kubectl_base delete -k "${KUSTOMIZATION}" --ignore-not-found >/dev/null 2>&1 || true
  fi
  echo "Mock kind resources are down. The kind cluster was left intact."
}

cmd_status() {
  need_cmd kubectl
  kubectl_base get ns "${MOCK_KIND_NAMESPACE}" >/dev/null
  echo "pods:"
  kubectl_ns get pods -o wide
  echo
  echo "deployments:"
  kubectl_ns get deploy -o wide
  echo
  echo "services:"
  kubectl_ns get svc -o wide
}

cmd_proof() {
  need_cmd curl
  need_cmd kubectl
  need_cmd python3

  mkdir -p "${ARTIFACT_DIR}"
  find "${ARTIFACT_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

  wait_for_deployment mock-upstream
  wait_for_deployment gateway
  kubectl_ns set env deployment/gateway GATEWAY_REQUEST_TIMEOUT=2s GATEWAY_CONCURRENCY_LIMIT=1
  wait_for_deployment gateway

  local pf_pid=""
  local pf_log="${ARTIFACT_DIR}/port-forward-gateway.log"

  cleanup() {
    if [[ -n "${pf_pid:-}" ]]; then
      kill "${pf_pid}" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup RETURN

  require_ports_free "Mock kind proof" "${MOCK_KIND_GATEWAY_LOCAL_PORT}"

  pf_pid="$(start_gateway_port_forward "${pf_log}")"
  wait_for_url "http://127.0.0.1:${MOCK_KIND_GATEWAY_LOCAL_PORT}/healthz"
  wait_for_url "http://127.0.0.1:${MOCK_KIND_GATEWAY_LOCAL_PORT}/readyz"
  write_runtime_config base GATEWAY_REQUEST_TIMEOUT=2s GATEWAY_CONCURRENCY_LIMIT=1
  capture_k8s_state base
  run_probe base base concurrency

  kubectl_ns set env deployment/gateway GATEWAY_REQUEST_TIMEOUT=100ms
  wait_for_deployment gateway
  kill "${pf_pid}" >/dev/null 2>&1 || true
  pf_pid="$(start_gateway_port_forward "${pf_log}")"
  wait_for_url "http://127.0.0.1:${MOCK_KIND_GATEWAY_LOCAL_PORT}/healthz"
  wait_for_url "http://127.0.0.1:${MOCK_KIND_GATEWAY_LOCAL_PORT}/readyz"
  sleep 0.5
  write_runtime_config timeout GATEWAY_REQUEST_TIMEOUT=100ms GATEWAY_CONCURRENCY_LIMIT=1
  capture_k8s_state timeout
  run_probe timeout timeout

  ARTIFACT_DIR_ENV="${ARTIFACT_DIR}" GATEWAY_URL_ENV="http://127.0.0.1:${MOCK_KIND_GATEWAY_LOCAL_PORT}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

artifact_dir = Path(os.environ["ARTIFACT_DIR_ENV"])
phases = ["base", "timeout"]
checks = {}
artifacts = {"port_forward_gateway_log": "port-forward-gateway.log"}
phase_manifests = {}
runtime_config = {}

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
    "mode": "mock_kind",
    "gateway_url": os.environ["GATEWAY_URL_ENV"],
    "cluster": os.environ.get("MOCK_KIND_CLUSTER", "inference-gateway"),
    "namespace": os.environ.get("MOCK_KIND_NAMESPACE", "inference-gateway-mock"),
    "kustomization": "deploy/k8s/mock-kind",
    "phase_manifests": phase_manifests,
    "runtime_config": runtime_config,
    "checks": checks,
    "artifacts": artifacts,
    "interpretation_limits": [
        "This manifest validates the isolated kind deployment with gateway and mock upstream pods.",
        "It does not validate the companion backend, cloud Kubernetes, or production autoscaling.",
    ],
}
(artifact_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

failed = [name for name, ok in checks.items() if not ok]
summary = [
    "# Mock Kind Proof Summary",
    "",
    f"- Gateway URL: {os.environ['GATEWAY_URL_ENV']}",
    f"- Phases: {', '.join(phases)}",
    f"- Checks passed: {sum(1 for ok in checks.values() if ok)}",
    f"- Checks failed: {len(failed)}",
    "",
    "## Failed Checks",
    "",
]
if failed:
    summary.extend(f"- `{name}`" for name in failed)
else:
    summary.append("- none")
summary.append("")
(artifact_dir / "summary.md").write_text("\n".join(summary))

if failed:
    print("Mock kind proof validation failed:", file=sys.stderr)
    for name in failed:
        print(f" - {name}", file=sys.stderr)
    sys.exit(1)
PY

  echo "Generated mock kind proof artifacts in ${ARTIFACT_DIR}"
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    up) shift; cmd_up "$@" ;;
    down) shift; cmd_down "$@" ;;
    status) shift; cmd_status "$@" ;;
    proof) shift; cmd_proof "$@" ;;
    -h|--help|help) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
