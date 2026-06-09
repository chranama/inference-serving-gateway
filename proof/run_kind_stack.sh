#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CAREER_ROOT="$(cd "${GATEWAY_REPO_ROOT}/.." && pwd)"
BACKEND_REPO_ROOT="${CAREER_ROOT}/llm-extraction-platform"
BACKEND_OVERLAY_FAKE="${BACKEND_REPO_ROOT}/deploy/k8s/overlays/local-observability-kind"
BACKEND_OVERLAY_LIVE="${BACKEND_REPO_ROOT}/deploy/k8s/overlays/local-live-llama-kind"
GATEWAY_KUSTOMIZATION_FAKE="${GATEWAY_REPO_ROOT}/deploy/k8s/local-kind-stack"
GATEWAY_KUSTOMIZATION_LIVE="${GATEWAY_REPO_ROOT}/deploy/k8s/local-kind-live-stack"
KIND_CONFIG="${BACKEND_REPO_ROOT}/deploy/k8s/kind/kind-config.yaml"
BACKEND_IMAGE_TAG="llm-server:dev"
GATEWAY_IMAGE_TAG="inference-serving-gateway:dev"
LLAMA_SERVER_IMAGE_TAG="${LLAMA_SERVER_IMAGE:-llmep-llama-server:b8069}"
POSTGRES_IMAGE_TAG="${POSTGRES_IMAGE:-postgres:16-alpine}"
REDIS_IMAGE_TAG="${REDIS_IMAGE:-redis:7-alpine}"
OTEL_COLLECTOR_IMAGE_TAG="${OTEL_COLLECTOR_IMAGE:-otel/opentelemetry-collector-contrib:0.122.1}"
JAEGER_IMAGE_TAG="${JAEGER_IMAGE:-jaegertracing/all-in-one:1.62.0}"
ARTIFACT_DIR="${SCRIPT_DIR}/artifacts/kind_stack"
RUNTIME_DIR="${GATEWAY_REPO_ROOT}/tmp/kind_stack"

: "${PHASE2_KIND_WORKFLOW:=live}"
: "${PHASE2_KIND_CLUSTER:=llm}"
: "${PHASE2_KIND_NAMESPACE:=llm}"
: "${PHASE2_KIND_API_LOCAL_PORT:=18080}"
: "${PHASE2_KIND_GATEWAY_LOCAL_PORT:=18084}"
: "${PHASE2_KIND_JAEGER_LOCAL_PORT:=16686}"
: "${PHASE2_KIND_LLAMA_LOCAL_PORT:=18088}"
: "${PHASE2_PROOF_USER_KEY:=proof-user-key}"
: "${PHASE2_PROOF_ADMIN_KEY:=proof-admin-key}"
: "${PHASE2_KIND_ENV_FILE:=${BACKEND_REPO_ROOT}/.env.docker}"
: "${PHASE2_KIND_REBUILD_LLAMA:=0}"
: "${PHASE2_KIND_PRELOAD_IMAGES:=1}"

case "${PHASE2_KIND_WORKFLOW}" in
  live)
    BACKEND_OVERLAY="${BACKEND_OVERLAY_LIVE}"
    GATEWAY_KUSTOMIZATION="${GATEWAY_KUSTOMIZATION_LIVE}"
    ;;
  fake)
    BACKEND_OVERLAY="${BACKEND_OVERLAY_FAKE}"
    GATEWAY_KUSTOMIZATION="${GATEWAY_KUSTOMIZATION_FAKE}"
    ;;
  *)
    echo "PHASE2_KIND_WORKFLOW must be live or fake; got: ${PHASE2_KIND_WORKFLOW}" >&2
    exit 2
    ;;
esac

usage() {
  cat <<'EOF'
Usage:
  proof/run_kind_stack.sh up
  proof/run_kind_stack.sh down
  proof/run_kind_stack.sh status
  proof/run_kind_stack.sh smoke
  proof/run_kind_stack.sh proof

This is the primary local Kubernetes-shaped path. By default it runs the
live-model workflow:

  PHASE2_KIND_WORKFLOW=live

Live mode mounts LLAMA_MODELS_DIR from the host into the kind node at /models and
runs a CPU-only llama.cpp model runtime in the cluster. Use
PHASE2_KIND_WORKFLOW=fake for the older deterministic fake-backend kind smoke.

The smoke command verifies the running stack without writing proof artifacts.
The proof command generates the review evidence bundle under proof/artifacts/.
EOF
}

clear_proof_outputs() {
  mkdir -p "${ARTIFACT_DIR}"
  rm -rf \
    "${ARTIFACT_DIR}/observability_latest" \
    "${ARTIFACT_DIR}/runtime" \
    "${ARTIFACT_DIR}/rendered"
  rm -f \
    "${ARTIFACT_DIR}/kind-config.live.yaml" \
    "${ARTIFACT_DIR}/jaeger-services.json" \
    "${ARTIFACT_DIR}/port-forward-api.log" \
    "${ARTIFACT_DIR}/port-forward-gateway.log" \
    "${ARTIFACT_DIR}/port-forward-jaeger.log" \
    "${ARTIFACT_DIR}/port-forward-llama-server.log"
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

load_env_file_if_present() {
  local env_file="$1"
  [[ -f "${env_file}" ]] || return 0

  local line key value
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if ! [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      continue
    fi
    if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    if [[ -z "${!key:-}" ]]; then
      export "${key}=${value}"
    fi
  done < "${env_file}"
}

prepare_live_model_env() {
  load_env_file_if_present "${PHASE2_KIND_ENV_FILE}"

  : "${LLAMA_MODEL_FILE:=/models/smollm2-360m-instruct/Q8_0.gguf}"
  : "${LLAMA_CTX_SIZE:=4096}"
  : "${LLAMA_THREADS:=8}"
  : "${LLAMA_BATCH:=256}"
  : "${LLAMA_UBATCH:=}"
  : "${LLAMA_N_GPU_LAYERS:=0}"
  : "${LLAMA_SEED:=0}"
  : "${LLAMA_TEMP:=0.7}"
  : "${LLAMA_TOP_P:=0.95}"
  : "${LLAMA_MLOCK:=1}"
  : "${LLAMA_NO_MMAP:=1}"
  : "${LLAMA_PARALLEL:=1}"

  if [[ -z "${LLAMA_MODELS_DIR:-}" ]]; then
    echo "LLAMA_MODELS_DIR is required for PHASE2_KIND_WORKFLOW=live." >&2
    echo "Set it directly or in ${PHASE2_KIND_ENV_FILE}." >&2
    exit 2
  fi
  if [[ "${LLAMA_MODEL_FILE}" != /models/* ]]; then
    echo "LLAMA_MODEL_FILE must point inside the /models mount; got: ${LLAMA_MODEL_FILE}" >&2
    exit 2
  fi
  if [[ "${LLAMA_N_GPU_LAYERS}" != "0" ]]; then
    echo "Live kind is CPU-only; set LLAMA_N_GPU_LAYERS=0." >&2
    exit 2
  fi
  export \
    LLAMA_MODEL_FILE \
    LLAMA_CTX_SIZE \
    LLAMA_THREADS \
    LLAMA_BATCH \
    LLAMA_UBATCH \
    LLAMA_N_GPU_LAYERS \
    LLAMA_SEED \
    LLAMA_TEMP \
    LLAMA_TOP_P \
    LLAMA_MLOCK \
    LLAMA_NO_MMAP \
    LLAMA_PARALLEL

  local rel_model_path host_model_file
  rel_model_path="${LLAMA_MODEL_FILE#/models/}"
  host_model_file="${LLAMA_MODELS_DIR%/}/${rel_model_path}"
  if [[ ! -f "${host_model_file}" ]]; then
    echo "GGUF model file not found for live kind workflow: ${host_model_file}" >&2
    exit 2
  fi
}

write_live_kind_config() {
  mkdir -p "${RUNTIME_DIR}"
  local generated="${RUNTIME_DIR}/kind-config.live.yaml"
  cat > "${generated}" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${PHASE2_KIND_CLUSTER}
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: "${LLAMA_MODELS_DIR}"
        containerPath: /models
        readOnly: true
EOF
  printf '%s\n' "${generated}"
}

verify_live_kind_mount() {
  docker exec "${PHASE2_KIND_CLUSTER}-control-plane" test -f "${LLAMA_MODEL_FILE}" || {
    echo "Existing kind cluster does not expose ${LLAMA_MODEL_FILE} inside the node." >&2
    echo "Delete and recreate it with: kind delete cluster --name ${PHASE2_KIND_CLUSTER}" >&2
    echo "Then rerun: PHASE2_KIND_WORKFLOW=live proof/run_kind_stack.sh up" >&2
    exit 2
  }
}

ensure_kind_cluster() {
  if kind get clusters | grep -qx "${PHASE2_KIND_CLUSTER}"; then
    if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
      verify_live_kind_mount
    fi
    return 0
  fi

  local config_path="${KIND_CONFIG}"
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    config_path="$(write_live_kind_config)"
  fi
  kind create cluster --config "${config_path}"
}

build_and_load_images() {
  ensure_image_present() {
    local image="$1"
    if ! docker image inspect "${image}" >/dev/null 2>&1; then
      docker pull "${image}"
    fi
  }

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

  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    if [[ "${PHASE2_KIND_REBUILD_LLAMA}" == "1" ]] || ! docker image inspect "${LLAMA_SERVER_IMAGE_TAG}" >/dev/null 2>&1; then
      docker build \
        -t "${LLAMA_SERVER_IMAGE_TAG}" \
        -f "${BACKEND_REPO_ROOT}/deploy/docker/Dockerfile.llama-server" \
        "${BACKEND_REPO_ROOT}"
    fi
    kind load docker-image "${LLAMA_SERVER_IMAGE_TAG}" --name "${PHASE2_KIND_CLUSTER}"
  fi

  if [[ "${PHASE2_KIND_PRELOAD_IMAGES}" == "1" ]]; then
    local image
    for image in \
      "${POSTGRES_IMAGE_TAG}" \
      "${REDIS_IMAGE_TAG}" \
      "${OTEL_COLLECTOR_IMAGE_TAG}" \
      "${JAEGER_IMAGE_TAG}"
    do
      ensure_image_present "${image}"
      kind load docker-image "${image}" --name "${PHASE2_KIND_CLUSTER}"
    done
  fi
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
  local timeout="${2:-240s}"
  kubectl_ns rollout status "deployment/${deployment_name}" --timeout="${timeout}"
}

render_backend_overlay() {
  if [[ "${PHASE2_KIND_WORKFLOW}" != "live" ]]; then
    kubectl kustomize "${BACKEND_OVERLAY}"
    return 0
  fi

  kubectl kustomize "${BACKEND_OVERLAY}" | python3 -c '
import json
import os
import sys

text = sys.stdin.read()
def config_value(name, default):
    return json.dumps(str(os.environ.get(name, default)))

values = {
    "__LLAMA_MODEL_FILE__": config_value("LLAMA_MODEL_FILE", "/models/smollm2-360m-instruct/Q8_0.gguf"),
    "__LLAMA_CTX_SIZE__": config_value("LLAMA_CTX_SIZE", "4096"),
    "__LLAMA_THREADS__": config_value("LLAMA_THREADS", "8"),
    "__LLAMA_BATCH__": config_value("LLAMA_BATCH", "256"),
    "__LLAMA_UBATCH__": config_value("LLAMA_UBATCH", ""),
    "__LLAMA_SEED__": config_value("LLAMA_SEED", "0"),
    "__LLAMA_TEMP__": config_value("LLAMA_TEMP", "0.7"),
    "__LLAMA_TOP_P__": config_value("LLAMA_TOP_P", "0.95"),
    "__LLAMA_MLOCK__": config_value("LLAMA_MLOCK", "1"),
    "__LLAMA_NO_MMAP__": config_value("LLAMA_NO_MMAP", "1"),
    "__LLAMA_PARALLEL__": config_value("LLAMA_PARALLEL", "1"),
}
for placeholder, value in values.items():
    text = text.replace(placeholder, value)
sys.stdout.write(text)
'
}

apply_backend_overlay() {
  mkdir -p "${RUNTIME_DIR}/rendered"
  local rendered="${RUNTIME_DIR}/rendered/backend-${PHASE2_KIND_WORKFLOW}.yaml"
  render_backend_overlay > "${rendered}"
  kubectl apply -f "${rendered}"
}

copy_runtime_outputs_to_artifacts() {
  mkdir -p "${ARTIFACT_DIR}"
  if [[ -f "${RUNTIME_DIR}/kind-config.live.yaml" ]]; then
    cp "${RUNTIME_DIR}/kind-config.live.yaml" "${ARTIFACT_DIR}/kind-config.live.yaml"
  fi
  if [[ -d "${RUNTIME_DIR}/rendered" ]]; then
    mkdir -p "${ARTIFACT_DIR}/rendered"
    cp -R "${RUNTIME_DIR}/rendered/." "${ARTIFACT_DIR}/rendered/"
  fi
}

apply_gateway_overlay() {
  kubectl apply -k "${GATEWAY_KUSTOMIZATION}"
}

delete_all_known_overlays() {
  kubectl delete -k "${GATEWAY_KUSTOMIZATION_LIVE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl delete -k "${GATEWAY_KUSTOMIZATION_FAKE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl delete -k "${BACKEND_OVERLAY_LIVE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl delete -k "${BACKEND_OVERLAY_FAKE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

cmd_up() {
  need_cmd docker
  need_cmd kind
  need_cmd kubectl
  need_cmd curl
  ensure_docker_ready

  mkdir -p "${RUNTIME_DIR}"
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    prepare_live_model_env
  fi

  ensure_kind_cluster
  build_and_load_images

  kubectl_ns delete job db-migrate --ignore-not-found >/dev/null 2>&1 || true
  kubectl_ns delete job seed-proof-keys --ignore-not-found >/dev/null 2>&1 || true

  apply_backend_overlay
  wait_for_job_complete "db-migrate"
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    wait_for_deployment "llama-server" "${PHASE2_KIND_LLAMA_ROLLOUT_TIMEOUT:-900s}"
  fi
  wait_for_deployment "api"

  apply_gateway_overlay
  wait_for_deployment "otel-collector"
  wait_for_deployment "jaeger"
  wait_for_deployment "extract-worker"
  wait_for_deployment "gateway"
  wait_for_job_complete "seed-proof-keys"

  echo "Phase 2 kind stack is up."
  echo "Workflow: ${PHASE2_KIND_WORKFLOW}"
  echo "Namespace: ${PHASE2_KIND_NAMESPACE}"
  echo "Backend overlay: ${BACKEND_OVERLAY}"
  echo "Integrated add-ons: ${GATEWAY_KUSTOMIZATION}"
  echo "Jaeger UI: kubectl -n ${PHASE2_KIND_NAMESPACE} port-forward svc/jaeger ${PHASE2_KIND_JAEGER_LOCAL_PORT}:16686"
  echo "Use proof/run_kind_stack.sh smoke for a no-artifact verification pass."
  echo "Use proof/run_kind_stack.sh proof to generate the observability evidence bundle."
}

cmd_down() {
  delete_all_known_overlays
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

cmd_smoke() {
  need_cmd kubectl
  need_cmd curl
  need_cmd python3
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    prepare_live_model_env
  fi

  local smoke_tmp
  smoke_tmp="$(mktemp -d "${TMPDIR:-/tmp}/kind-smoke.XXXXXX")"
  local api_pf_log="${smoke_tmp}/port-forward-api.log"
  local gateway_pf_log="${smoke_tmp}/port-forward-gateway.log"
  local llama_pf_log="${smoke_tmp}/port-forward-llama-server.log"
  local api_pf_pid=""
  local gateway_pf_pid=""
  local llama_pf_pid=""

  cleanup() {
    if [[ -n "${llama_pf_pid:-}" ]]; then
      kill "${llama_pf_pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${gateway_pf_pid:-}" ]]; then
      kill "${gateway_pf_pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${api_pf_pid:-}" ]]; then
      kill "${api_pf_pid}" >/dev/null 2>&1 || true
    fi
    rm -rf "${smoke_tmp}"
  }
  trap cleanup RETURN

  api_pf_pid="$(start_port_forward "svc/api" "${PHASE2_KIND_API_LOCAL_PORT}:8000" "${api_pf_log}")"
  gateway_pf_pid="$(start_port_forward "svc/gateway" "${PHASE2_KIND_GATEWAY_LOCAL_PORT}:8080" "${gateway_pf_log}")"
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    llama_pf_pid="$(start_port_forward "svc/llama-server" "${PHASE2_KIND_LLAMA_LOCAL_PORT}:8080" "${llama_pf_log}")"
  fi

  local api_url="http://127.0.0.1:${PHASE2_KIND_API_LOCAL_PORT}"
  local gateway_url="http://127.0.0.1:${PHASE2_KIND_GATEWAY_LOCAL_PORT}"
  local llama_url="http://127.0.0.1:${PHASE2_KIND_LLAMA_LOCAL_PORT}"

  wait_for_url "${api_url}/healthz"
  wait_for_url "${api_url}/readyz"
  wait_for_url "${gateway_url}/healthz"
  wait_for_url "${gateway_url}/readyz"
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    wait_for_url "${llama_url}/health"
    curl -fsS "${llama_url}/v1/models" >/dev/null
  fi

  curl -fsS \
    -H "X-API-Key: ${PHASE2_PROOF_USER_KEY}" \
    "${api_url}/v1/models/status" >/dev/null

  local payload
  payload='{"schema_id":"sroie_receipt_v1","text":"Company: ACME\nDate: 2024-01-01\nTotal: 10.00\nAddress: 123 Main St","temperature":0.0,"max_new_tokens":256,"cache":false,"repair":true}'

  local sync_body="${smoke_tmp}/sync_extract.json"
  curl -fsS \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${PHASE2_PROOF_USER_KEY}" \
    -H "X-Request-ID: kind-smoke-sync-request" \
    -H "X-Trace-ID: kind-smoke-sync-trace" \
    -d "${payload}" \
    "${gateway_url}/v1/extract" >"${sync_body}"

  local sync_model
  sync_model="$(python3 - <<'PY' "${sync_body}" "${PHASE2_KIND_WORKFLOW}"
import json
import sys

path = sys.argv[1]
workflow = sys.argv[2]
payload = json.load(open(path))
model = str(payload.get("model", ""))
data = payload.get("data") or {}
missing = [key for key in ("company", "date", "total") if key not in data]
if missing:
    raise SystemExit(f"sync extract missing fields: {', '.join(missing)}")
if workflow == "live" and "llama.cpp/" not in model:
    raise SystemExit(f"sync extract did not use live llama.cpp model: {model}")
print(model)
PY
)"

  local submit_body="${smoke_tmp}/async_submit.json"
  curl -fsS \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${PHASE2_PROOF_USER_KEY}" \
    -H "X-Request-ID: kind-smoke-async-submit-request" \
    -H "X-Trace-ID: kind-smoke-async-trace" \
    -d "${payload}" \
    "${gateway_url}/v1/extract/jobs" >"${submit_body}"

  local job_id
  job_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["job_id"])' "${submit_body}")"

  local status_body="${smoke_tmp}/async_status.json"
  local final_status=""
  for _ in $(seq 1 80); do
    curl -fsS \
      -H "X-API-Key: ${PHASE2_PROOF_USER_KEY}" \
      -H "X-Request-ID: kind-smoke-async-poll-request" \
      -H "X-Trace-ID: kind-smoke-async-trace" \
      "${gateway_url}/v1/extract/jobs/${job_id}" >"${status_body}"
    final_status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "${status_body}")"
    if [[ "${final_status}" == "succeeded" ]]; then
      break
    fi
    if [[ "${final_status}" == "failed" ]]; then
      cat "${status_body}" >&2
      echo >&2
      echo "Async extract failed during kind smoke." >&2
      return 1
    fi
    sleep 0.25
  done
  if [[ "${final_status}" != "succeeded" ]]; then
    echo "Timed out waiting for async extract job ${job_id}." >&2
    return 1
  fi

  python3 - <<'PY' "${status_body}" "${PHASE2_KIND_WORKFLOW}"
import json
import sys

path = sys.argv[1]
workflow = sys.argv[2]
payload = json.load(open(path))
model = str(payload.get("model", ""))
result = payload.get("result") or {}
missing = [key for key in ("company", "date", "total") if key not in result]
if missing:
    raise SystemExit(f"async extract missing fields: {', '.join(missing)}")
if workflow == "live" and "llama.cpp/" not in model:
    raise SystemExit(f"async extract did not use live llama.cpp model: {model}")
PY

  echo "Kind smoke passed."
  echo "Workflow: ${PHASE2_KIND_WORKFLOW}"
  echo "Gateway: ${gateway_url}"
  echo "Model: ${sync_model}"
  echo "Async job: ${job_id}"
}

cmd_proof() {
  need_cmd kubectl
  need_cmd curl
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    prepare_live_model_env
  fi

  clear_proof_outputs
  copy_runtime_outputs_to_artifacts
  local api_pf_log="${ARTIFACT_DIR}/port-forward-api.log"
  local gateway_pf_log="${ARTIFACT_DIR}/port-forward-gateway.log"
  local jaeger_pf_log="${ARTIFACT_DIR}/port-forward-jaeger.log"
  local llama_pf_log="${ARTIFACT_DIR}/port-forward-llama-server.log"
  local api_pf_pid=""
  local gateway_pf_pid=""
  local jaeger_pf_pid=""
  local llama_pf_pid=""

  cleanup() {
    if [[ -n "${llama_pf_pid:-}" ]]; then
      kill "${llama_pf_pid}" >/dev/null 2>&1 || true
    fi
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
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    llama_pf_pid="$(start_port_forward "svc/llama-server" "${PHASE2_KIND_LLAMA_LOCAL_PORT}:8080" "${llama_pf_log}")"
  fi

  wait_for_url "http://127.0.0.1:${PHASE2_KIND_API_LOCAL_PORT}/healthz"
  wait_for_url "http://127.0.0.1:${PHASE2_KIND_GATEWAY_LOCAL_PORT}/healthz"
  wait_for_url "http://127.0.0.1:${PHASE2_KIND_JAEGER_LOCAL_PORT}"
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    wait_for_url "http://127.0.0.1:${PHASE2_KIND_LLAMA_LOCAL_PORT}/health"
  fi

  env \
    LLM_EXTRACTION_PLATFORM_BASE_URL="http://127.0.0.1:${PHASE2_KIND_API_LOCAL_PORT}" \
    LLM_EXTRACTION_PLATFORM_API_KEY="${PHASE2_PROOF_USER_KEY}" \
    LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY="${PHASE2_PROOF_ADMIN_KEY}" \
    GATEWAY_BASE_URL="http://127.0.0.1:${PHASE2_KIND_GATEWAY_LOCAL_PORT}" \
    JAEGER_BASE_URL="http://127.0.0.1:${PHASE2_KIND_JAEGER_LOCAL_PORT}" \
    OTEL_GATEWAY_SERVICE_NAME="inference-serving-gateway" \
    OTEL_BACKEND_SERVICE_NAME="llm-extraction-platform" \
    OTEL_WORKER_SERVICE_NAME="llm-extraction-platform-worker" \
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

  local runtime_dir="${ARTIFACT_DIR}/runtime"
  mkdir -p "${runtime_dir}"
  {
    echo "workflow=${PHASE2_KIND_WORKFLOW}"
    echo "backend_overlay=${BACKEND_OVERLAY}"
    echo "gateway_kustomization=${GATEWAY_KUSTOMIZATION}"
    echo "api_base_url=http://127.0.0.1:${PHASE2_KIND_API_LOCAL_PORT}"
    echo "gateway_base_url=http://127.0.0.1:${PHASE2_KIND_GATEWAY_LOCAL_PORT}"
    if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
      echo "llama_base_url=http://127.0.0.1:${PHASE2_KIND_LLAMA_LOCAL_PORT}"
      echo "llama_model_file=${LLAMA_MODEL_FILE:-}"
    fi
  } > "${runtime_dir}/workflow.env"

  curl -fsS \
    -H "X-API-Key: ${PHASE2_PROOF_USER_KEY}" \
    "http://127.0.0.1:${PHASE2_KIND_API_LOCAL_PORT}/v1/models/status" \
    > "${runtime_dir}/models_status.json" || true

  kubectl_ns logs deployment/api --tail=200 > "${runtime_dir}/backend-api.logs.txt" || true
  kubectl_ns logs deployment/extract-worker --tail=200 > "${runtime_dir}/worker.logs.txt" || true
  kubectl_ns logs deployment/gateway --tail=200 > "${runtime_dir}/gateway.logs.txt" || true
  if [[ "${PHASE2_KIND_WORKFLOW}" == "live" ]]; then
    curl -fsS "http://127.0.0.1:${PHASE2_KIND_LLAMA_LOCAL_PORT}/health" \
      > "${runtime_dir}/llama_health.json" || true
    curl -fsS "http://127.0.0.1:${PHASE2_KIND_LLAMA_LOCAL_PORT}/v1/models" \
      > "${runtime_dir}/llama_models.json" || true
    kubectl_ns logs deployment/llama-server --tail=200 > "${runtime_dir}/llama-server.logs.txt" || true
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
    smoke) shift; cmd_smoke "$@" ;;
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
