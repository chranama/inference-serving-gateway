#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CAREER_ROOT="$(cd "${GATEWAY_REPO_ROOT}/.." && pwd)"
BACKEND_REPO_ROOT="${CAREER_ROOT}/llm-extraction-platform"
BACKEND_OVERLAY="${BACKEND_REPO_ROOT}/deploy/k8s/overlays/local-observability-kind"
GATEWAY_KUSTOMIZATION="${GATEWAY_REPO_ROOT}/deploy/k8s/local-kind-stack"
KIND_CONFIG="${BACKEND_REPO_ROOT}/deploy/k8s/kind/kind-config.yaml"
BACKEND_IMAGE_TAG="llm-server:dev"
GATEWAY_IMAGE_TAG="inference-serving-gateway:dev"
ARTIFACT_DIR="${SCRIPT_DIR}/artifacts/kind_stack"

: "${PHASE2_KIND_CLUSTER:=llm}"
: "${PHASE2_KIND_NAMESPACE:=llm}"
: "${PHASE2_KIND_API_LOCAL_PORT:=18080}"
: "${PHASE2_KIND_GATEWAY_LOCAL_PORT:=18084}"
: "${PHASE2_KIND_JAEGER_LOCAL_PORT:=16686}"
: "${PHASE2_PROOF_USER_KEY:=proof-user-key}"
: "${PHASE2_PROOF_ADMIN_KEY:=proof-admin-key}"

usage() {
  cat <<'EOF'
Usage:
  proof/run_kind_stack.sh up
  proof/run_kind_stack.sh down
  proof/run_kind_stack.sh status
  proof/run_kind_stack.sh proof

This is the Kubernetes-shaped Phase 2 path. It complements
proof/run_local_stack.sh, which uses Docker Compose for infra and
host-run processes for the app services.
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
    echo "Docker is required for the Phase 2 kind stack, but the Docker daemon is not reachable." >&2
    exit 1
  fi
}

ensure_kind_cluster() {
  if kind get clusters | grep -qx "${PHASE2_KIND_CLUSTER}"; then
    return 0
  fi
  kind create cluster --config "${KIND_CONFIG}"
}

build_and_load_images() {
  docker build \
    -t "${BACKEND_IMAGE_TAG}" \
    -f "${BACKEND_REPO_ROOT}/deploy/docker/Dockerfile.server" \
    "${BACKEND_REPO_ROOT}"
  kind load docker-image "${BACKEND_IMAGE_TAG}" --name "${PHASE2_KIND_CLUSTER}"

  docker build \
    -t "${GATEWAY_IMAGE_TAG}" \
    -f "${GATEWAY_REPO_ROOT}/Dockerfile" \
    "${GATEWAY_REPO_ROOT}"
  kind load docker-image "${GATEWAY_IMAGE_TAG}" --name "${PHASE2_KIND_CLUSTER}"
}

kubectl_ns() {
  kubectl -n "${PHASE2_KIND_NAMESPACE}" "$@"
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

wait_for_jaeger_services() {
  local url="$1"
  shift
  local required_services=("$@")
  local attempts=80
  local services_json=""

  for _ in $(seq 1 "${attempts}"); do
    if services_json="$(curl -fsS "${url}" 2>/dev/null)"; then
      local missing=0
      local service=""
      for service in "${required_services[@]}"; do
        if ! grep -q "\"${service}\"" <<<"${services_json}"; then
          missing=1
          break
        fi
      done
      if [[ "${missing}" -eq 0 ]]; then
        printf '%s' "${services_json}"
        return 0
      fi
    fi
    sleep 0.5
  done

  if [[ -n "${services_json}" ]]; then
    printf '%s' "${services_json}"
  fi
  return 1
}

start_port_forward() {
  local resource="$1"
  local mapping="$2"
  local log_path="$3"
  : >"${log_path}"
  kubectl_ns port-forward "${resource}" "${mapping}" >"${log_path}" 2>&1 &
  echo $!
}

wait_for_job_complete() {
  local job_name="$1"
  kubectl_ns wait --for=condition=complete "job/${job_name}" --timeout=240s
}

wait_for_deployment() {
  local deployment_name="$1"
  kubectl_ns rollout status "deployment/${deployment_name}" --timeout=240s
}

cmd_up() {
  need_cmd docker
  need_cmd kind
  need_cmd kubectl
  need_cmd curl
  ensure_docker_ready

  mkdir -p "${ARTIFACT_DIR}"

  ensure_kind_cluster
  build_and_load_images

  kubectl_ns delete job db-migrate --ignore-not-found >/dev/null 2>&1 || true
  kubectl_ns delete job seed-proof-keys --ignore-not-found >/dev/null 2>&1 || true

  kubectl apply -k "${BACKEND_OVERLAY}"
  wait_for_job_complete "db-migrate"
  wait_for_deployment "api"

  kubectl apply -k "${GATEWAY_KUSTOMIZATION}"
  wait_for_deployment "otel-collector"
  wait_for_deployment "jaeger"
  wait_for_deployment "extract-worker"
  wait_for_deployment "gateway"
  wait_for_job_complete "seed-proof-keys"

  echo "Phase 2 kind stack is up."
  echo "Namespace: ${PHASE2_KIND_NAMESPACE}"
  echo "Backend overlay: ${BACKEND_OVERLAY}"
  echo "Integrated add-ons: ${GATEWAY_KUSTOMIZATION}"
  echo "Jaeger UI: kubectl -n ${PHASE2_KIND_NAMESPACE} port-forward svc/jaeger ${PHASE2_KIND_JAEGER_LOCAL_PORT}:16686"
  echo "Use proof/run_kind_stack.sh proof to run the observability pack via port-forward."
}

cmd_down() {
  kubectl delete -k "${GATEWAY_KUSTOMIZATION}" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -k "${BACKEND_OVERLAY}" --ignore-not-found >/dev/null 2>&1 || true
  echo "Phase 2 kind resources are down. The kind cluster was left intact."
}

cmd_status() {
  kubectl get ns "${PHASE2_KIND_NAMESPACE}" >/dev/null 2>&1 || {
    echo "Namespace ${PHASE2_KIND_NAMESPACE} not found."
    exit 1
  }
  echo "pods:"
  kubectl_ns get pods -o wide
  echo
  echo "services:"
  kubectl_ns get svc
  echo
  echo "jobs:"
  kubectl_ns get jobs
}

cmd_proof() {
  need_cmd kubectl
  need_cmd curl

  mkdir -p "${ARTIFACT_DIR}"
  local api_pf_log="${ARTIFACT_DIR}/port-forward-api.log"
  local gateway_pf_log="${ARTIFACT_DIR}/port-forward-gateway.log"
  local jaeger_pf_log="${ARTIFACT_DIR}/port-forward-jaeger.log"
  local api_pf_pid=""
  local gateway_pf_pid=""
  local jaeger_pf_pid=""

  cleanup() {
    if [[ -n "${jaeger_pf_pid:-}" ]]; then
      kill "${jaeger_pf_pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${gateway_pf_pid:-}" ]]; then
      kill "${gateway_pf_pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${api_pf_pid:-}" ]]; then
      kill "${api_pf_pid}" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup RETURN

  api_pf_pid="$(start_port_forward "svc/api" "${PHASE2_KIND_API_LOCAL_PORT}:8000" "${api_pf_log}")"
  gateway_pf_pid="$(start_port_forward "svc/gateway" "${PHASE2_KIND_GATEWAY_LOCAL_PORT}:8080" "${gateway_pf_log}")"
  jaeger_pf_pid="$(start_port_forward "svc/jaeger" "${PHASE2_KIND_JAEGER_LOCAL_PORT}:16686" "${jaeger_pf_log}")"

  wait_for_url "http://127.0.0.1:${PHASE2_KIND_API_LOCAL_PORT}/healthz"
  wait_for_url "http://127.0.0.1:${PHASE2_KIND_GATEWAY_LOCAL_PORT}/healthz"
  wait_for_url "http://127.0.0.1:${PHASE2_KIND_JAEGER_LOCAL_PORT}"

  env \
    LLM_EXTRACTION_PLATFORM_BASE_URL="http://127.0.0.1:${PHASE2_KIND_API_LOCAL_PORT}" \
    LLM_EXTRACTION_PLATFORM_API_KEY="${PHASE2_PROOF_USER_KEY}" \
    LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY="${PHASE2_PROOF_ADMIN_KEY}" \
    GATEWAY_BASE_URL="http://127.0.0.1:${PHASE2_KIND_GATEWAY_LOCAL_PORT}" \
    "${SCRIPT_DIR}/generate_llm_extraction_platform_observability_pack.sh" \
    "${ARTIFACT_DIR}/observability_latest"

  local jaeger_services_json="${ARTIFACT_DIR}/jaeger-services.json"
  if ! wait_for_jaeger_services \
    "http://127.0.0.1:${PHASE2_KIND_JAEGER_LOCAL_PORT}/api/services" \
    "inference-serving-gateway" \
    "llm-extraction-platform" \
    "llm-extraction-platform-worker" >"${jaeger_services_json}"; then
    echo "Jaeger did not register all expected services in time." >&2
    echo "Last Jaeger services payload:" >&2
    cat "${jaeger_services_json}" >&2
    return 1
  fi

  echo "Jaeger services captured at ${jaeger_services_json}"
  echo "Jaeger UI is available during this proof run at http://127.0.0.1:${PHASE2_KIND_JAEGER_LOCAL_PORT}"
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    up) shift; cmd_up "$@" ;;
    down) shift; cmd_down "$@" ;;
    status) shift; cmd_status "$@" ;;
    proof) shift; cmd_proof "$@" ;;
    ""|-h|--help|help) usage ;;
    *)
      echo "Unknown command: ${cmd}" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"
