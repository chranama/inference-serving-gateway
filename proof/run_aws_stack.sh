#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_REPO_ROOT="${BACKEND_REPO_ROOT:-$(cd "${REPO_ROOT}/../llm-extraction-platform" && pwd)}"

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-llm-runtime-dev}"
NAMESPACE="${NAMESPACE:-llm}"
TF_DIR="${TF_DIR:-${REPO_ROOT}/deploy/aws/terraform/environments/dev}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${SCRIPT_DIR}/artifacts/aws_stack/latest}"

BACKEND_OVERLAY="${BACKEND_OVERLAY:-${BACKEND_REPO_ROOT}/deploy/k8s/overlays/aws-eks}"
GATEWAY_OVERLAY="${GATEWAY_OVERLAY:-${REPO_ROOT}/deploy/k8s/aws-eks}"
BACKEND_PLACEHOLDER="012345678901.dkr.ecr.us-east-1.amazonaws.com/llm-server:aws-dev-latest"
GATEWAY_PLACEHOLDER="012345678901.dkr.ecr.us-east-1.amazonaws.com/inference-serving-gateway:aws-dev-latest"

PROOF_USER_KEY="${PROOF_USER_KEY:-aws-proof-user-key}"
PROOF_ADMIN_KEY="${PROOF_ADMIN_KEY:-aws-proof-admin-key}"
ALB_CONTROLLER_VERSION="${ALB_CONTROLLER_VERSION:-v2.14.1}"
ALB_CONTROLLER_POLICY_NAME="${ALB_CONTROLLER_POLICY_NAME:-AWSLoadBalancerControllerIAMPolicy}"
CURL_RESOLVE_ARGS=()

usage() {
  cat <<'USAGE'
Usage:
  proof/run_aws_stack.sh preflight
  proof/run_aws_stack.sh terraform-plan
  proof/run_aws_stack.sh terraform-apply
  proof/run_aws_stack.sh kubeconfig
  proof/run_aws_stack.sh install-cloudwatch
  proof/run_aws_stack.sh install-alb-controller
  proof/run_aws_stack.sh render
  proof/run_aws_stack.sh create-secret
  proof/run_aws_stack.sh deploy
  proof/run_aws_stack.sh status
  proof/run_aws_stack.sh smoke
  proof/run_aws_stack.sh inspect
  proof/run_aws_stack.sh redeploy
  proof/run_aws_stack.sh delete-workloads
  proof/run_aws_stack.sh delete-addons
  proof/run_aws_stack.sh terraform-destroy

Environment:
  AWS_REGION                  default: us-east-1
  CLUSTER_NAME                default: llm-runtime-dev
  NAMESPACE                   default: llm
  BACKEND_REPO_ROOT           default: ../llm-extraction-platform
  GATEWAY_IMAGE               optional explicit ECR image URI:tag
  BACKEND_IMAGE               optional explicit ECR image URI:tag
  DATABASE_URL                optional explicit backend database URL
  REDIS_URL                   optional explicit backend Redis URL
  PROOF_USER_KEY              default: aws-proof-user-key
  PROOF_ADMIN_KEY             default: aws-proof-admin-key
  ARTIFACT_DIR                default: proof/artifacts/aws_stack/latest

The harness assumes the bounded dev Terraform substrate has been applied before
deploying workloads. It creates a Kubernetes Secret from environment values and
Terraform/AWS outputs; no live secret values are committed to the repository.
USAGE
}

log() {
  printf '[aws-stack] %s\n' "$*" >&2
}

fail() {
  printf '[aws-stack] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

ensure_dir() {
  mkdir -p "$1"
}

terraform_json_or_empty() {
  if [[ -d "${TF_DIR}/.terraform" ]]; then
    terraform -chdir="${TF_DIR}" output -json 2>/dev/null || true
  fi
}

terraform_required_json() {
  local output
  output="$(terraform_json_or_empty)"
  [[ -n "${output}" ]] || fail "Terraform outputs are unavailable. Run terraform-apply first or set explicit image/data env vars."
  printf '%s\n' "${output}"
}

default_gateway_image() {
  local tf_json repo_url
  tf_json="$(terraform_json_or_empty)"
  repo_url="$(printf '%s\n' "${tf_json}" | jq -r '.ecr_summary.value.gateway_url // empty' 2>/dev/null || true)"
  if [[ -n "${repo_url}" ]]; then
    printf '%s:aws-dev-latest\n' "${repo_url}"
  else
    printf '%s\n' "${GATEWAY_PLACEHOLDER}"
  fi
}

default_backend_image() {
  local tf_json repo_url
  tf_json="$(terraform_json_or_empty)"
  repo_url="$(printf '%s\n' "${tf_json}" | jq -r '.ecr_summary.value.backend_url // empty' 2>/dev/null || true)"
  if [[ -n "${repo_url}" ]]; then
    printf '%s:aws-dev-latest\n' "${repo_url}"
  else
    printf '%s\n' "${BACKEND_PLACEHOLDER}"
  fi
}

gateway_image() {
  printf '%s\n' "${GATEWAY_IMAGE:-$(default_gateway_image)}"
}

backend_image() {
  printf '%s\n' "${BACKEND_IMAGE:-$(default_backend_image)}"
}

preflight() {
  need_cmd terraform
  need_cmd kubectl
  need_cmd jq
  need_cmd python3
  need_cmd curl

  [[ -d "${BACKEND_REPO_ROOT}" ]] || fail "BACKEND_REPO_ROOT does not exist: ${BACKEND_REPO_ROOT}"
  [[ -d "${BACKEND_OVERLAY}" ]] || fail "Backend AWS overlay does not exist: ${BACKEND_OVERLAY}"
  [[ -d "${GATEWAY_OVERLAY}" ]] || fail "Gateway AWS overlay does not exist: ${GATEWAY_OVERLAY}"

  if ! command -v aws >/dev/null 2>&1; then
    log "aws CLI is not installed; render-only validation can run, but live AWS commands cannot."
  fi
  if ! command -v helm >/dev/null 2>&1; then
    log "helm is not installed; install-alb-controller cannot run until Helm is installed."
  fi
  if ! command -v eksctl >/dev/null 2>&1; then
    log "eksctl is not installed; install-alb-controller cannot create the IRSA service account."
  fi

  log "preflight complete"
}

terraform_plan() {
  need_cmd terraform
  terraform -chdir="${TF_DIR}" init
  terraform -chdir="${TF_DIR}" validate
  terraform -chdir="${TF_DIR}" plan -out=tfplan
}

terraform_apply() {
  need_cmd terraform
  terraform -chdir="${TF_DIR}" apply tfplan
}

terraform_destroy() {
  need_cmd terraform
  terraform -chdir="${TF_DIR}" destroy
}

kubeconfig() {
  need_cmd aws
  aws eks update-kubeconfig \
    --region "${AWS_REGION}" \
    --name "${CLUSTER_NAME}"
}

install_cloudwatch() {
  need_cmd aws
  log "installing or updating amazon-cloudwatch-observability add-on"
  if aws eks describe-addon \
    --region "${AWS_REGION}" \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name amazon-cloudwatch-observability >/dev/null 2>&1; then
    aws eks update-addon \
      --region "${AWS_REGION}" \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name amazon-cloudwatch-observability \
      --resolve-conflicts OVERWRITE
  else
    aws eks create-addon \
      --region "${AWS_REGION}" \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name amazon-cloudwatch-observability \
      --resolve-conflicts OVERWRITE
  fi
}

install_alb_controller() {
  need_cmd aws
  need_cmd curl
  need_cmd helm
  need_cmd eksctl

  local account_id policy_arn policy_file tf_json vpc_id
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  policy_arn="arn:aws:iam::${account_id}:policy/${ALB_CONTROLLER_POLICY_NAME}"
  policy_file="${ARTIFACT_DIR}/alb-controller-iam-policy.json"
  tf_json="$(terraform_required_json)"
  vpc_id="$(printf '%s\n' "${tf_json}" | jq -r '.network_summary.value.vpc_id // empty')"
  [[ -n "${vpc_id}" ]] || fail "VPC ID is missing from Terraform outputs"
  ensure_dir "${ARTIFACT_DIR}"

  if ! aws iam get-policy --policy-arn "${policy_arn}" >/dev/null 2>&1; then
    log "creating ${ALB_CONTROLLER_POLICY_NAME}"
    curl -fsSL \
      "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${ALB_CONTROLLER_VERSION}/docs/install/iam_policy.json" \
      -o "${policy_file}"
    aws iam create-policy \
      --policy-name "${ALB_CONTROLLER_POLICY_NAME}" \
      --policy-document "file://${policy_file}" >/dev/null
  fi

  eksctl utils associate-iam-oidc-provider \
    --cluster "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --approve

  eksctl create iamserviceaccount \
    --cluster "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --namespace kube-system \
    --name aws-load-balancer-controller \
    --attach-policy-arn "${policy_arn}" \
    --approve \
    --override-existing-serviceaccounts

  helm repo add eks https://aws.github.io/eks-charts >/dev/null
  helm repo update >/dev/null
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system \
    --set "clusterName=${CLUSTER_NAME}" \
    --set "region=${AWS_REGION}" \
    --set "vpcId=${vpc_id}" \
    --set "serviceAccount.create=false" \
    --set "serviceAccount.name=aws-load-balancer-controller"

  kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=180s
}

render_with_images() {
  local overlay image_placeholder image_value
  overlay="$1"
  image_placeholder="$2"
  image_value="$3"

  kubectl kustomize "${overlay}" | IMAGE_PLACEHOLDER="${image_placeholder}" IMAGE_VALUE="${image_value}" python3 -c '
import os
import sys

placeholder = os.environ["IMAGE_PLACEHOLDER"]
value = os.environ["IMAGE_VALUE"]
text = sys.stdin.read()
sys.stdout.write(text.replace(placeholder, value))
'
}

render() {
  need_cmd kubectl
  need_cmd python3
  need_cmd jq

  local rendered_dir backend_yaml gateway_yaml
  rendered_dir="${ARTIFACT_DIR}/rendered"
  backend_yaml="${rendered_dir}/backend.yaml"
  gateway_yaml="${rendered_dir}/gateway.yaml"
  ensure_dir "${rendered_dir}"

  log "rendering backend overlay"
  render_with_images "${BACKEND_OVERLAY}" "${BACKEND_PLACEHOLDER}" "$(backend_image)" > "${backend_yaml}"

  log "rendering gateway overlay"
  render_with_images "${GATEWAY_OVERLAY}" "${GATEWAY_PLACEHOLDER}" "$(gateway_image)" > "${gateway_yaml}"

  {
    echo "backend_image=$(backend_image)"
    echo "gateway_image=$(gateway_image)"
    echo "backend_overlay=${BACKEND_OVERLAY}"
    echo "gateway_overlay=${GATEWAY_OVERLAY}"
  } > "${rendered_dir}/render.env"

  log "rendered manifests in ${rendered_dir}"
}

derive_database_url() {
  need_cmd aws
  need_cmd jq
  need_cmd python3

  local tf_json secret_arn secret_json db_host db_port db_name db_user db_password
  tf_json="$(terraform_required_json)"
  secret_arn="$(printf '%s\n' "${tf_json}" | jq -r '.managed_data_summary.value.postgres_master_secret_arn // empty')"
  db_host="$(printf '%s\n' "${tf_json}" | jq -r '.managed_data_summary.value.postgres_endpoint')"
  db_port="$(printf '%s\n' "${tf_json}" | jq -r '.managed_data_summary.value.postgres_port')"
  db_name="$(printf '%s\n' "${tf_json}" | jq -r '.managed_data_summary.value.postgres_db_name')"

  [[ -n "${secret_arn}" && "${secret_arn}" != "null" ]] || fail "Postgres master secret ARN is missing from Terraform outputs"
  secret_json="$(aws secretsmanager get-secret-value --secret-id "${secret_arn}" --query SecretString --output text)"
  db_user="$(printf '%s\n' "${secret_json}" | jq -r '.username')"
  db_password="$(printf '%s\n' "${secret_json}" | jq -r '.password')"

  DB_USER="${db_user}" DB_PASSWORD="${db_password}" DB_HOST="${db_host}" DB_PORT="${db_port}" DB_NAME="${db_name}" python3 - <<'PY'
import os
from urllib.parse import quote

user = quote(os.environ["DB_USER"], safe="")
password = quote(os.environ["DB_PASSWORD"], safe="")
host = os.environ["DB_HOST"]
port = os.environ["DB_PORT"]
name = os.environ["DB_NAME"]
print(f"postgresql+asyncpg://{user}:{password}@{host}:{port}/{name}")
PY
}

derive_redis_url() {
  need_cmd jq

  local tf_json redis_host redis_port
  tf_json="$(terraform_required_json)"
  redis_host="$(printf '%s\n' "${tf_json}" | jq -r '.managed_data_summary.value.redis_endpoint')"
  redis_port="$(printf '%s\n' "${tf_json}" | jq -r '.managed_data_summary.value.redis_port')"
  printf 'redis://%s:%s/0\n' "${redis_host}" "${redis_port}"
}

create_secret() {
  need_cmd kubectl

  local database_url redis_url
  database_url="${DATABASE_URL:-$(derive_database_url)}"
  redis_url="${REDIS_URL:-$(derive_redis_url)}"

  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "${NAMESPACE}" create secret generic llm-secrets \
    --from-literal="API_KEY=${PROOF_USER_KEY}" \
    --from-literal="ADMIN_API_KEY=${PROOF_ADMIN_KEY}" \
    --from-literal="DATABASE_URL=${database_url}" \
    --from-literal="REDIS_URL=${redis_url}" \
    --from-literal="HF_TOKEN=${HF_TOKEN:-}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

  log "created/updated Kubernetes Secret ${NAMESPACE}/llm-secrets"
}

deploy() {
  need_cmd kubectl
  create_secret
  render

  kubectl apply -f "${ARTIFACT_DIR}/rendered/backend.yaml"
  kubectl apply -f "${ARTIFACT_DIR}/rendered/gateway.yaml"

  kubectl -n "${NAMESPACE}" wait --for=condition=complete job/db-migrate --timeout=180s
  kubectl -n "${NAMESPACE}" wait --for=condition=complete job/seed-proof-keys --timeout=180s
  kubectl -n "${NAMESPACE}" rollout status deployment/api --timeout=180s
  kubectl -n "${NAMESPACE}" rollout status deployment/extract-worker --timeout=180s
  kubectl -n "${NAMESPACE}" rollout status deployment/gateway --timeout=180s
  kubectl -n "${NAMESPACE}" rollout status deployment/otel-collector --timeout=180s
  kubectl -n "${NAMESPACE}" rollout status deployment/jaeger --timeout=180s
}

status() {
  need_cmd kubectl
  ensure_dir "${ARTIFACT_DIR}/runtime"
  kubectl -n "${NAMESPACE}" get pods -o wide > "${ARTIFACT_DIR}/runtime/pods.txt"
  kubectl -n "${NAMESPACE}" get svc -o wide > "${ARTIFACT_DIR}/runtime/services.txt"
  kubectl -n "${NAMESPACE}" get ingress -o wide > "${ARTIFACT_DIR}/runtime/ingress.txt"
  kubectl -n "${NAMESPACE}" describe ingress gateway > "${ARTIFACT_DIR}/runtime/gateway.ingress.describe.txt" || true
  kubectl -n "${NAMESPACE}" get events --sort-by=.metadata.creationTimestamp > "${ARTIFACT_DIR}/runtime/events.txt"
  log "captured runtime status in ${ARTIFACT_DIR}/runtime"
}

alb_host() {
  kubectl -n "${NAMESPACE}" get ingress gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true
}

wait_for_alb() {
  local host
  for _ in $(seq 1 90); do
    host="$(alb_host)"
    if [[ -n "${host}" ]]; then
      printf '%s\n' "${host}"
      return 0
    fi
    sleep 5
  done
  fail "ALB hostname did not appear on ingress/gateway"
}

curl_json() {
  local method url api_key body_prefix body headers status
  method="$1"
  url="$2"
  api_key="$3"
  body="$4"
  body_prefix="$5"

  headers="${body_prefix}.headers"
  body_file="${body_prefix}.body.json"
  status="$(curl -sS -D "${headers}" -o "${body_file}" -w '%{http_code}' \
    "${CURL_RESOLVE_ARGS[@]}" \
    -X "${method}" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${api_key}" \
    -d "${body}" \
    "${url}")"
  printf '%s\n' "${status}" > "${body_prefix}.status"
}

curl_get() {
  local url api_key body_prefix headers body_file status
  url="$1"
  api_key="$2"
  body_prefix="$3"
  headers="${body_prefix}.headers"
  body_file="${body_prefix}.body.json"
  status="$(curl -sS -D "${headers}" -o "${body_file}" -w '%{http_code}' \
    "${CURL_RESOLVE_ARGS[@]}" \
    -H "X-API-Key: ${api_key}" \
    "${url}")"
  printf '%s\n' "${status}" > "${body_prefix}.status"
}

configure_curl_resolve() {
  local host ip
  host="$1"
  ip="$(ALB_HOST="${host}" python3 - <<'PY'
import os
import socket

host = os.environ["ALB_HOST"]
for family, socktype, proto, _canonname, sockaddr in socket.getaddrinfo(
    host, 80, proto=socket.IPPROTO_TCP
):
    if family == socket.AF_INET:
        print(sockaddr[0])
        break
else:
    raise SystemExit(f"could not resolve IPv4 address for {host}")
PY
)"
  CURL_RESOLVE_ARGS=(--resolve "${host}:80:${ip}")
}

smoke() {
  need_cmd kubectl
  need_cmd curl
  need_cmd jq

  local smoke_dir host base_url payload sync_status submit_status job_id job_url status final_status
  smoke_dir="${ARTIFACT_DIR}/smoke"
  ensure_dir "${smoke_dir}"
  host="$(wait_for_alb)"
  configure_curl_resolve "${host}"
  base_url="http://${host}"
  printf '%s\n' "${base_url}" > "${smoke_dir}/alb_url.txt"

  curl -sS -D "${smoke_dir}/health.headers" -o "${smoke_dir}/health.body.json" -w '%{http_code}' \
    "${CURL_RESOLVE_ARGS[@]}" \
    "${base_url}/healthz" > "${smoke_dir}/health.status"

  payload='{"schema_id":"sroie_receipt_v1","text":"Vendor: ACME\nTotal: 10.00","cache":false,"repair":true}'

  curl_json "POST" "${base_url}/v1/extract" "${PROOF_USER_KEY}" "${payload}" "${smoke_dir}/sync_extract"
  sync_status="$(cat "${smoke_dir}/sync_extract.status")"
  [[ "${sync_status}" == "200" ]] || fail "sync extract smoke failed with HTTP ${sync_status}"

  curl_json "POST" "${base_url}/v1/extract/jobs" "${PROOF_USER_KEY}" "${payload}" "${smoke_dir}/async_submit"
  submit_status="$(cat "${smoke_dir}/async_submit.status")"
  [[ "${submit_status}" == "202" ]] || fail "async submit smoke failed with HTTP ${submit_status}"

  job_id="$(jq -r '.job_id // empty' "${smoke_dir}/async_submit.body.json")"
  [[ -n "${job_id}" ]] || fail "async submit response did not include job_id"
  job_url="${base_url}/v1/extract/jobs/${job_id}"

  for _ in $(seq 1 60); do
    curl_get "${job_url}" "${PROOF_USER_KEY}" "${smoke_dir}/async_status"
    final_status="$(cat "${smoke_dir}/async_status.status")"
    [[ "${final_status}" == "200" ]] || fail "async status poll failed with HTTP ${final_status}"
    status="$(jq -r '.status // empty' "${smoke_dir}/async_status.body.json")"
    if [[ "${status}" == "succeeded" ]]; then
      break
    fi
    if [[ "${status}" == "failed" ]]; then
      fail "async job failed"
    fi
    sleep 2
  done

  [[ "$(jq -r '.status // empty' "${smoke_dir}/async_status.body.json")" == "succeeded" ]] || fail "async job did not finish before timeout"

  {
    echo "{"
    echo "  \"alb_url\": \"${base_url}\","
    echo "  \"sync_status\": ${sync_status},"
    echo "  \"async_submit_status\": ${submit_status},"
    echo "  \"async_job_id\": \"${job_id}\","
    echo "  \"async_final_status\": \"$(jq -r '.status' "${smoke_dir}/async_status.body.json")\""
    echo "}"
  } > "${smoke_dir}/summary.json"

  log "smoke proof captured in ${smoke_dir}"
}

capture_port_forward_metrics() {
  local service local_port remote_port output_file pid
  service="$1"
  local_port="$2"
  remote_port="$3"
  output_file="$4"

  kubectl -n "${NAMESPACE}" port-forward "svc/${service}" "${local_port}:${remote_port}" >/dev/null 2>&1 &
  pid="$!"
  sleep 3
  curl -sS "http://127.0.0.1:${local_port}/metrics" > "${output_file}" || true
  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" >/dev/null 2>&1 || true
}

inspect() {
  need_cmd kubectl
  need_cmd curl

  local inspect_dir log_group
  inspect_dir="${ARTIFACT_DIR}/inspect"
  ensure_dir "${inspect_dir}"

  kubectl -n "${NAMESPACE}" logs deployment/gateway --tail=200 > "${inspect_dir}/gateway.logs.txt" || true
  kubectl -n "${NAMESPACE}" logs deployment/api --tail=200 > "${inspect_dir}/backend-api.logs.txt" || true
  kubectl -n "${NAMESPACE}" logs deployment/extract-worker --tail=200 > "${inspect_dir}/worker.logs.txt" || true
  kubectl -n "${NAMESPACE}" logs deployment/otel-collector --tail=200 > "${inspect_dir}/otel-collector.logs.txt" || true

  capture_port_forward_metrics gateway 18080 8080 "${inspect_dir}/gateway.metrics.txt"
  capture_port_forward_metrics api 18000 8000 "${inspect_dir}/backend.metrics.txt"

  if command -v aws >/dev/null 2>&1; then
    aws logs describe-log-groups \
      --region "${AWS_REGION}" \
      --log-group-name-prefix "/aws/containerinsights/${CLUSTER_NAME}" \
      > "${inspect_dir}/cloudwatch-log-groups.json" || true

    log_group="$(jq -r '.logGroups[]?.logGroupName | select(endswith("/application"))' "${inspect_dir}/cloudwatch-log-groups.json" 2>/dev/null | head -1 || true)"
    if [[ -n "${log_group}" ]]; then
      aws logs filter-log-events \
        --region "${AWS_REGION}" \
        --log-group-name "${log_group}" \
        --filter-pattern 'request_id' \
        --max-items 50 \
        > "${inspect_dir}/cloudwatch-correlated-events.json" || true
    fi
  fi

  log "inspection artifacts captured in ${inspect_dir}"
}

redeploy() {
  need_cmd kubectl

  local redeploy_dir
  redeploy_dir="${ARTIFACT_DIR}/redeploy"
  ensure_dir "${redeploy_dir}"

  kubectl -n "${NAMESPACE}" get deployment api extract-worker gateway \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.template.spec.containers[*]}{.name}{" "}{.image}{" "}{.imagePullPolicy}{"\n"}{end}{end}' \
    > "${redeploy_dir}/before-images.txt"

  kubectl -n "${NAMESPACE}" rollout restart deployment/api deployment/extract-worker deployment/gateway \
    > "${redeploy_dir}/rollout-restart.txt"
  kubectl -n "${NAMESPACE}" rollout status deployment/api --timeout=180s \
    > "${redeploy_dir}/api-rollout-status.txt"
  kubectl -n "${NAMESPACE}" rollout status deployment/extract-worker --timeout=180s \
    > "${redeploy_dir}/worker-rollout-status.txt"
  kubectl -n "${NAMESPACE}" rollout status deployment/gateway --timeout=180s \
    > "${redeploy_dir}/gateway-rollout-status.txt"

  kubectl -n "${NAMESPACE}" get pods -o wide > "${redeploy_dir}/pods-after.txt"
  kubectl -n "${NAMESPACE}" get events --sort-by=.metadata.creationTimestamp > "${redeploy_dir}/events-after.txt"

  smoke
  cp "${ARTIFACT_DIR}/smoke/summary.json" "${redeploy_dir}/post-redeploy-smoke-summary.json"

  log "redeploy proof captured in ${redeploy_dir}"
}

delete_workloads() {
  need_cmd kubectl
  render
  kubectl delete -f "${ARTIFACT_DIR}/rendered/gateway.yaml" --ignore-not-found=true
  kubectl delete -f "${ARTIFACT_DIR}/rendered/backend.yaml" --ignore-not-found=true
  kubectl -n "${NAMESPACE}" delete secret llm-secrets --ignore-not-found=true
}

delete_addons() {
  need_cmd aws

  local account_id policy_arn
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  policy_arn="arn:aws:iam::${account_id}:policy/${ALB_CONTROLLER_POLICY_NAME}"

  if command -v helm >/dev/null 2>&1; then
    helm uninstall aws-load-balancer-controller --namespace kube-system >/dev/null 2>&1 || true
  fi

  if command -v eksctl >/dev/null 2>&1; then
    eksctl delete iamserviceaccount \
      --cluster "${CLUSTER_NAME}" \
      --region "${AWS_REGION}" \
      --namespace kube-system \
      --name aws-load-balancer-controller \
      --wait || true
  fi

  if aws eks describe-addon \
    --region "${AWS_REGION}" \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name amazon-cloudwatch-observability >/dev/null 2>&1; then
    aws eks delete-addon \
      --region "${AWS_REGION}" \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name amazon-cloudwatch-observability >/dev/null
    aws eks wait addon-deleted \
      --region "${AWS_REGION}" \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name amazon-cloudwatch-observability || true
  fi

  aws iam delete-policy --policy-arn "${policy_arn}" >/dev/null 2>&1 || true
}

main() {
  local command_name
  command_name="${1:-}"
  case "${command_name}" in
    preflight) preflight ;;
    terraform-plan) terraform_plan ;;
    terraform-apply) terraform_apply ;;
    kubeconfig) kubeconfig ;;
    install-cloudwatch) install_cloudwatch ;;
    install-alb-controller) install_alb_controller ;;
    render) render ;;
    create-secret) create_secret ;;
    deploy) deploy ;;
    status) status ;;
    smoke) smoke ;;
    inspect) inspect ;;
    redeploy) redeploy ;;
    delete-workloads) delete_workloads ;;
    delete-addons) delete_addons ;;
    terraform-destroy) terraform_destroy ;;
    ""|help|-h|--help) usage ;;
    *) usage; fail "unknown command: ${command_name}" ;;
  esac
}

main "$@"
