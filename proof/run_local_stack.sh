#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CAREER_ROOT="$(cd "${GATEWAY_REPO_ROOT}/.." && pwd)"
BACKEND_REPO_ROOT="${CAREER_ROOT}/llm-extraction-platform"
BACKEND_SERVER_DIR="${BACKEND_REPO_ROOT}/server"
COMPOSE_FILE="${BACKEND_REPO_ROOT}/deploy/compose/docker-compose.yml"
RUNTIME_DIR="${SCRIPT_DIR}/runtime/local_stack"
LOG_DIR="${RUNTIME_DIR}/logs"
PID_DIR="${RUNTIME_DIR}/pids"
STATE_DIR="${RUNTIME_DIR}/state"
ENV_FILE="${RUNTIME_DIR}/local-stack.env"

BACKEND_LOG="${LOG_DIR}/backend.log"
WORKER_LOG="${LOG_DIR}/worker.log"
GATEWAY_LOG="${LOG_DIR}/gateway.log"

BACKEND_PID_FILE="${PID_DIR}/backend.pid"
WORKER_PID_FILE="${PID_DIR}/worker.pid"
GATEWAY_PID_FILE="${PID_DIR}/gateway.pid"

DEFAULT_DATABASE_URL="postgresql+asyncpg://llm:llm@127.0.0.1:5433/llm"
DEFAULT_REDIS_URL="redis://127.0.0.1:6379/0"
DEFAULT_BACKEND_URL="http://127.0.0.1:8000"
DEFAULT_GATEWAY_URL="http://127.0.0.1:18082"

: "${PHASE2_APP_ROOT:=${BACKEND_REPO_ROOT}}"
: "${PHASE2_APP_PROFILE:=test}"
: "${PHASE2_MODELS_PROFILE:=observability-proof}"
: "${PHASE2_MODELS_YAML:=${BACKEND_REPO_ROOT}/proof/fixtures/models.observability-proof.yaml}"
: "${PHASE2_SCHEMAS_DIR:=${BACKEND_REPO_ROOT}/schemas/model_output}"
: "${PHASE2_DATABASE_URL:=${DEFAULT_DATABASE_URL}}"
: "${PHASE2_REDIS_URL:=${DEFAULT_REDIS_URL}}"
: "${PHASE2_BACKEND_HOST:=127.0.0.1}"
: "${PHASE2_BACKEND_PORT:=8000}"
: "${PHASE2_GATEWAY_HOST:=127.0.0.1}"
: "${PHASE2_GATEWAY_PORT:=18082}"
: "${PHASE2_PG_HOST_PORT:=5433}"
: "${PHASE2_REDIS_HOST_PORT:=6379}"
: "${PHASE2_PROM_HOST_PORT:=9091}"
: "${PHASE2_GRAFANA_PORT:=3000}"
: "${PHASE2_OTEL_COLLECTOR_PORT:=4318}"
: "${PHASE2_OTEL_COLLECTOR_HEALTH_PORT:=13133}"
: "${PHASE2_JAEGER_PORT:=16686}"
: "${PHASE2_PROOF_GATEWAY_PORT:=18083}"
: "${PHASE2_PROOF_USER_KEY:=proof-user-key}"
: "${PHASE2_PROOF_ADMIN_KEY:=proof-admin-key}"
: "${PHASE2_WITH_OBS:=1}"
: "${PHASE2_WITH_OTEL:=1}"
: "${PHASE2_OTEL_EXPORTER_OTLP_ENDPOINT:=http://127.0.0.1:${PHASE2_OTEL_COLLECTOR_PORT}/v1/traces}"
: "${PHASE2_BACKEND_OTEL_SERVICE_NAME:=llm-extraction-platform}"
: "${PHASE2_WORKER_OTEL_SERVICE_NAME:=llm-extraction-platform-worker}"
: "${PHASE2_GATEWAY_OTEL_SERVICE_NAME:=inference-serving-gateway}"

usage() {
  cat <<'EOF'
Usage:
  proof/run_local_stack.sh up
  proof/run_local_stack.sh down
  proof/run_local_stack.sh restart
  proof/run_local_stack.sh status
  proof/run_local_stack.sh proof

Optional environment overrides:
  PHASE2_WITH_OBS=0                       Skip Prometheus/Grafana host profile on `up`
  PHASE2_DATABASE_URL=...                 Override backend DB URL
  PHASE2_REDIS_URL=...                    Override backend Redis URL
  PHASE2_MODELS_YAML=...                  Override proof models fixture
  PHASE2_SCHEMAS_DIR=...                  Override schema directory
  PHASE2_PROOF_USER_KEY=...               Override proof standard API key
  PHASE2_PROOF_ADMIN_KEY=...              Override proof admin API key
  PHASE2_WITH_OTEL=0                      Skip Collector/Jaeger on `up`
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
    echo "Docker is required for the Phase 2 local stack, but the Docker daemon is not reachable." >&2
    echo "Start Docker Desktop (or otherwise make the daemon available), then rerun:" >&2
    echo "  proof/run_local_stack.sh up" >&2
    exit 1
  fi
}

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local attempts="${3:-80}"
  for _ in $(seq 1 "${attempts}"); do
    if python3 - <<PY >/dev/null 2>&1
import socket
sock = socket.socket()
sock.settimeout(1.0)
try:
    sock.connect(("${host}", int("${port}")))
finally:
    sock.close()
PY
    then
      return 0
    fi
    sleep 0.25
  done
  echo "Timed out waiting for TCP ${host}:${port}" >&2
  return 1
}

wait_for_database_url() {
  local database_url="$1"
  local attempts="${2:-80}"
  for _ in $(seq 1 "${attempts}"); do
    if env DATABASE_URL="${database_url}" /Users/chranama/career/llm-extraction-platform/server/.venv/bin/python - <<'PY' >/dev/null 2>&1
import asyncio
import os
import asyncpg

def normalize_database_url(raw: str) -> str:
    if raw.startswith("postgresql+asyncpg://"):
        return "postgresql://" + raw[len("postgresql+asyncpg://"):]
    return raw

async def main() -> None:
    conn = await asyncpg.connect(normalize_database_url(os.environ["DATABASE_URL"]))
    try:
        await conn.execute("SELECT 1")
    finally:
        await conn.close()

asyncio.run(main())
PY
    then
      return 0
    fi
    sleep 0.5
  done
  echo "Timed out waiting for database connection: ${database_url}" >&2
  return 1
}

need_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "Missing required file: ${path}" >&2
    exit 1
  fi
}

ensure_layout() {
  mkdir -p "${LOG_DIR}" "${PID_DIR}" "${STATE_DIR}"
}

write_env_file() {
  ensure_layout
  cat >"${ENV_FILE}" <<EOF
APP_ROOT=${PHASE2_APP_ROOT}
APP_PROFILE=${PHASE2_APP_PROFILE}
MODELS_PROFILE=${PHASE2_MODELS_PROFILE}
MODELS_YAML=${PHASE2_MODELS_YAML}
SCHEMAS_DIR=${PHASE2_SCHEMAS_DIR}
DATABASE_URL=${PHASE2_DATABASE_URL}
REDIS_ENABLED=1
REDIS_URL=${PHASE2_REDIS_URL}
EDGE_MODE=behind_gateway
OTEL_ENABLED=${PHASE2_WITH_OTEL}
OTEL_EXPORTER_OTLP_ENDPOINT=${PHASE2_OTEL_EXPORTER_OTLP_ENDPOINT}
EOF
}

compose_cmd() {
  local -a cmd=(docker compose -f "${COMPOSE_FILE}")
  local profile
  for profile in "$@"; do
    cmd+=(--profile "${profile}")
  done
  printf '%q ' "${cmd[@]}"
  printf '\n'
}

compose_up_selected() {
  local -a profiles=(infra-host)
  if [[ "${PHASE2_WITH_OBS}" == "1" ]]; then
    profiles+=(obs-host)
  fi
  if [[ "${PHASE2_WITH_OTEL}" == "1" ]]; then
    profiles+=(otel-host)
  fi
  local -a cmd=(docker compose -f "${COMPOSE_FILE}")
  local profile
  for profile in "${profiles[@]}"; do
    cmd+=(--profile "${profile}")
  done
  cmd+=(up -d --remove-orphans)
  env \
    POSTGRES_HOST_PORT="${PHASE2_PG_HOST_PORT}" \
    REDIS_HOST_PORT="${PHASE2_REDIS_HOST_PORT}" \
    PROM_HOST_PORT="${PHASE2_PROM_HOST_PORT}" \
    GRAFANA_PORT="${PHASE2_GRAFANA_PORT}" \
    OTEL_COLLECTOR_HOST_PORT="${PHASE2_OTEL_COLLECTOR_PORT}" \
    OTEL_COLLECTOR_HEALTH_HOST_PORT="${PHASE2_OTEL_COLLECTOR_HEALTH_PORT}" \
    JAEGER_PORT="${PHASE2_JAEGER_PORT}" \
    "${cmd[@]}"
}

compose_down_selected() {
  local -a profiles=(infra-host)
  if [[ "${PHASE2_WITH_OBS}" == "1" ]]; then
    profiles+=(obs-host)
  fi
  if [[ "${PHASE2_WITH_OTEL}" == "1" ]]; then
    profiles+=(otel-host)
  fi
  local -a cmd=(docker compose -f "${COMPOSE_FILE}")
  local profile
  for profile in "${profiles[@]}"; do
    cmd+=(--profile "${profile}")
  done
  cmd+=(down --remove-orphans)
  env \
    POSTGRES_HOST_PORT="${PHASE2_PG_HOST_PORT}" \
    REDIS_HOST_PORT="${PHASE2_REDIS_HOST_PORT}" \
    PROM_HOST_PORT="${PHASE2_PROM_HOST_PORT}" \
    GRAFANA_PORT="${PHASE2_GRAFANA_PORT}" \
    OTEL_COLLECTOR_HOST_PORT="${PHASE2_OTEL_COLLECTOR_PORT}" \
    OTEL_COLLECTOR_HEALTH_HOST_PORT="${PHASE2_OTEL_COLLECTOR_HEALTH_PORT}" \
    JAEGER_PORT="${PHASE2_JAEGER_PORT}" \
    "${cmd[@]}"
}

is_pid_running() {
  local pid_file="$1"
  if [[ ! -f "${pid_file}" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "${pid_file}")"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" >/dev/null 2>&1
}

stop_pid_file() {
  local pid_file="$1"
  if ! is_pid_running "${pid_file}"; then
    rm -f "${pid_file}"
    return 0
  fi
  local pid
  pid="$(cat "${pid_file}")"
  kill "${pid}" >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill -9 "${pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${pid_file}"
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

start_backend_process() {
  if is_pid_running "${BACKEND_PID_FILE}"; then
    return 0
  fi
  : >"${BACKEND_LOG}"
  (
    cd "${BACKEND_SERVER_DIR}"
    nohup env \
      APP_ROOT="${PHASE2_APP_ROOT}" \
      APP_PROFILE="${PHASE2_APP_PROFILE}" \
      MODELS_PROFILE="${PHASE2_MODELS_PROFILE}" \
      MODELS_YAML="${PHASE2_MODELS_YAML}" \
      SCHEMAS_DIR="${PHASE2_SCHEMAS_DIR}" \
      DATABASE_URL="${PHASE2_DATABASE_URL}" \
      REDIS_ENABLED=1 \
      REDIS_URL="${PHASE2_REDIS_URL}" \
      EDGE_MODE=behind_gateway \
      OTEL_ENABLED="${PHASE2_WITH_OTEL}" \
      OTEL_SERVICE_NAME="${PHASE2_BACKEND_OTEL_SERVICE_NAME}" \
      OTEL_EXPORTER_OTLP_ENDPOINT="${PHASE2_OTEL_EXPORTER_OTLP_ENDPOINT}" \
      /Users/chranama/career/llm-extraction-platform/server/.venv/bin/python \
      -m uvicorn llm_server.main:app \
      --host "${PHASE2_BACKEND_HOST}" \
      --port "${PHASE2_BACKEND_PORT}" \
      >"${BACKEND_LOG}" 2>&1 &
    echo $! >"${BACKEND_PID_FILE}"
  )
}

start_worker_process() {
  if is_pid_running "${WORKER_PID_FILE}"; then
    return 0
  fi
  : >"${WORKER_LOG}"
  (
    cd "${BACKEND_SERVER_DIR}"
    nohup env \
      APP_ROOT="${PHASE2_APP_ROOT}" \
      APP_PROFILE="${PHASE2_APP_PROFILE}" \
      MODELS_PROFILE="${PHASE2_MODELS_PROFILE}" \
      MODELS_YAML="${PHASE2_MODELS_YAML}" \
      SCHEMAS_DIR="${PHASE2_SCHEMAS_DIR}" \
      DATABASE_URL="${PHASE2_DATABASE_URL}" \
      REDIS_ENABLED=1 \
      REDIS_URL="${PHASE2_REDIS_URL}" \
      EDGE_MODE=behind_gateway \
      OTEL_ENABLED="${PHASE2_WITH_OTEL}" \
      OTEL_SERVICE_NAME="${PHASE2_WORKER_OTEL_SERVICE_NAME}" \
      OTEL_EXPORTER_OTLP_ENDPOINT="${PHASE2_OTEL_EXPORTER_OTLP_ENDPOINT}" \
      /Users/chranama/career/llm-extraction-platform/server/.venv/bin/python \
      -m llm_server.worker.extract_jobs \
      --poll-timeout-seconds 1 \
      >"${WORKER_LOG}" 2>&1 &
    echo $! >"${WORKER_PID_FILE}"
  )
}

start_gateway_process() {
  if is_pid_running "${GATEWAY_PID_FILE}"; then
    return 0
  fi
  : >"${GATEWAY_LOG}"
  (
    cd "${GATEWAY_REPO_ROOT}"
    nohup env \
      GATEWAY_LISTEN_ADDR="${PHASE2_GATEWAY_HOST}:${PHASE2_GATEWAY_PORT}" \
      GATEWAY_UPSTREAM_BASE_URL="${DEFAULT_BACKEND_URL}" \
      GATEWAY_OTEL_ENABLED="${PHASE2_WITH_OTEL}" \
      GATEWAY_OTEL_SERVICE_NAME="${PHASE2_GATEWAY_OTEL_SERVICE_NAME}" \
      GATEWAY_OTEL_EXPORTER_OTLP_ENDPOINT="${PHASE2_OTEL_EXPORTER_OTLP_ENDPOINT}" \
      go run ./cmd/gateway \
      >"${GATEWAY_LOG}" 2>&1 &
    echo $! >"${GATEWAY_PID_FILE}"
  )
}

run_migrations() {
  (
    cd "${BACKEND_SERVER_DIR}"
    env \
      APP_ROOT="${PHASE2_APP_ROOT}" \
      APP_PROFILE="${PHASE2_APP_PROFILE}" \
      DATABASE_URL="${PHASE2_DATABASE_URL}" \
      /Users/chranama/career/llm-extraction-platform/server/.venv/bin/python \
      -m alembic \
      -c "${BACKEND_SERVER_DIR}/alembic.ini" \
      upgrade head
  )
}

seed_proof_keys() {
  (
    cd "${BACKEND_SERVER_DIR}"
    env \
      APP_ROOT="${PHASE2_APP_ROOT}" \
      APP_PROFILE="${PHASE2_APP_PROFILE}" \
      DATABASE_URL="${PHASE2_DATABASE_URL}" \
      PROOF_USER_KEY="${PHASE2_PROOF_USER_KEY}" \
      PROOF_ADMIN_KEY="${PHASE2_PROOF_ADMIN_KEY}" \
      /Users/chranama/career/llm-extraction-platform/server/.venv/bin/python - <<'PY'
import asyncio
import os
from sqlalchemy import select

from llm_server.db.models import ApiKey, RoleTable
from llm_server.db.session import get_sessionmaker

PROOF_USER_KEY = os.environ["PROOF_USER_KEY"]
PROOF_ADMIN_KEY = os.environ["PROOF_ADMIN_KEY"]

async def ensure_role(session, name: str) -> RoleTable:
    role = (await session.execute(select(RoleTable).where(RoleTable.name == name))).scalar_one_or_none()
    if role is None:
        role = RoleTable(name=name)
        session.add(role)
        await session.flush()
    return role

async def ensure_key(session, *, key: str, role_id: int | None) -> None:
    row = (await session.execute(select(ApiKey).where(ApiKey.key == key))).scalar_one_or_none()
    if row is None:
        session.add(ApiKey(key=key, active=True, role_id=role_id, quota_monthly=None, quota_used=0))
        return
    changed = False
    if not row.active:
        row.active = True
        changed = True
    if row.role_id != role_id:
        row.role_id = role_id
        changed = True
    if changed:
        session.add(row)

async def main() -> None:
    sessionmaker = get_sessionmaker()
    async with sessionmaker() as session:
        admin = await ensure_role(session, "admin")
        standard = await ensure_role(session, "standard")
        await ensure_key(session, key=PROOF_USER_KEY, role_id=standard.id)
        await ensure_key(session, key=PROOF_ADMIN_KEY, role_id=admin.id)
        await session.commit()

asyncio.run(main())
PY
  )
}

show_status_line() {
  local label="$1"
  local pid_file="$2"
  local health_url="${3:-}"
  local process_state="stopped"
  if is_pid_running "${pid_file}"; then
    process_state="running"
  fi
  if [[ -n "${health_url}" ]]; then
    if curl -fsS "${health_url}" >/dev/null 2>&1; then
      echo "${label}: ${process_state} (${health_url} healthy)"
    else
      echo "${label}: ${process_state} (${health_url} unhealthy)"
    fi
  else
    echo "${label}: ${process_state}"
  fi
}

cmd_up() {
  need_cmd docker
  need_cmd curl
  need_cmd go
  need_cmd nohup
  need_cmd python3
  ensure_docker_ready
  need_file "${PHASE2_MODELS_YAML}"
  need_file "${PHASE2_SCHEMAS_DIR}/sroie_receipt_v1.json"
  ensure_layout
  write_env_file
  compose_up_selected
  wait_for_tcp "127.0.0.1" "${PHASE2_PG_HOST_PORT}" 120
  wait_for_database_url "${PHASE2_DATABASE_URL}" 120
  wait_for_tcp "127.0.0.1" "${PHASE2_REDIS_HOST_PORT}" 120
  if [[ "${PHASE2_WITH_OTEL}" == "1" ]]; then
    wait_for_tcp "127.0.0.1" "${PHASE2_OTEL_COLLECTOR_PORT}" 120
    wait_for_url "http://127.0.0.1:${PHASE2_JAEGER_PORT}"
  fi
  run_migrations
  seed_proof_keys
  start_backend_process
  start_worker_process
  start_gateway_process
  wait_for_url "${DEFAULT_BACKEND_URL}/healthz"
  wait_for_url "${DEFAULT_GATEWAY_URL}/healthz"
  echo "Phase 2 local stack is up."
  echo "Backend: ${DEFAULT_BACKEND_URL}"
  echo "Gateway: ${DEFAULT_GATEWAY_URL}"
  echo "Prometheus: http://127.0.0.1:${PHASE2_PROM_HOST_PORT} (if PHASE2_WITH_OBS=1)"
  echo "Grafana: http://127.0.0.1:${PHASE2_GRAFANA_PORT} (if PHASE2_WITH_OBS=1)"
  echo "OTel Collector: http://127.0.0.1:${PHASE2_OTEL_COLLECTOR_PORT}/v1/traces (if PHASE2_WITH_OTEL=1)"
  echo "Jaeger: http://127.0.0.1:${PHASE2_JAEGER_PORT} (if PHASE2_WITH_OTEL=1)"
  echo "Env contract: ${ENV_FILE}"
}

cmd_down() {
  stop_pid_file "${GATEWAY_PID_FILE}"
  stop_pid_file "${WORKER_PID_FILE}"
  stop_pid_file "${BACKEND_PID_FILE}"
  if command -v docker >/dev/null 2>&1; then
    compose_down_selected || true
  fi
  echo "Phase 2 local stack is down."
}

cmd_restart() {
  cmd_down
  cmd_up
}

cmd_status() {
  show_status_line "backend" "${BACKEND_PID_FILE}" "${DEFAULT_BACKEND_URL}/healthz"
  show_status_line "worker" "${WORKER_PID_FILE}"
  show_status_line "gateway" "${GATEWAY_PID_FILE}" "${DEFAULT_GATEWAY_URL}/healthz"
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1 && docker compose -f "${COMPOSE_FILE}" ps >/dev/null 2>&1; then
      echo "infra:"
      env \
        POSTGRES_HOST_PORT="${PHASE2_PG_HOST_PORT}" \
        REDIS_HOST_PORT="${PHASE2_REDIS_HOST_PORT}" \
        PROM_HOST_PORT="${PHASE2_PROM_HOST_PORT}" \
        GRAFANA_PORT="${PHASE2_GRAFANA_PORT}" \
        OTEL_COLLECTOR_HOST_PORT="${PHASE2_OTEL_COLLECTOR_PORT}" \
        OTEL_COLLECTOR_HEALTH_HOST_PORT="${PHASE2_OTEL_COLLECTOR_HEALTH_PORT}" \
        JAEGER_PORT="${PHASE2_JAEGER_PORT}" \
        docker compose -f "${COMPOSE_FILE}" ps postgres_host redis_host prometheus_host grafana otel_collector_host jaeger || true
    else
      echo "infra: docker unavailable"
    fi
  fi
  echo "logs:"
  echo "  backend -> ${BACKEND_LOG}"
  echo "  worker  -> ${WORKER_LOG}"
  echo "  gateway -> ${GATEWAY_LOG}"
}

cmd_proof() {
  if ! is_pid_running "${BACKEND_PID_FILE}" || ! is_pid_running "${WORKER_PID_FILE}" || ! is_pid_running "${GATEWAY_PID_FILE}"; then
    echo "Local stack is not fully running. Run: proof/run_local_stack.sh up" >&2
    exit 1
  fi
  wait_for_url "${DEFAULT_BACKEND_URL}/healthz"
  wait_for_url "${DEFAULT_GATEWAY_URL}/healthz"
  env \
    LLM_EXTRACTION_PLATFORM_BASE_URL="${DEFAULT_BACKEND_URL}" \
    LLM_EXTRACTION_PLATFORM_API_KEY="${PHASE2_PROOF_USER_KEY}" \
    LLM_EXTRACTION_PLATFORM_ADMIN_API_KEY="${PHASE2_PROOF_ADMIN_KEY}" \
    GATEWAY_BASE_URL="${DEFAULT_GATEWAY_URL}" \
    GATEWAY_LOG_PATH="${GATEWAY_LOG}" \
    JAEGER_BASE_URL="http://127.0.0.1:${PHASE2_JAEGER_PORT}" \
    OTEL_GATEWAY_SERVICE_NAME="${PHASE2_GATEWAY_OTEL_SERVICE_NAME}" \
    OTEL_BACKEND_SERVICE_NAME="${PHASE2_BACKEND_OTEL_SERVICE_NAME}" \
    OTEL_WORKER_SERVICE_NAME="${PHASE2_WORKER_OTEL_SERVICE_NAME}" \
    "${SCRIPT_DIR}/generate_llm_extraction_platform_observability_pack.sh"
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    up) shift; cmd_up "$@" ;;
    down) shift; cmd_down "$@" ;;
    restart) shift; cmd_restart "$@" ;;
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
