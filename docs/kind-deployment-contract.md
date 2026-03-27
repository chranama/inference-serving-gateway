# Phase 2 Kind Deployment Contract

This is the Kubernetes-shaped Phase 2 path for the integrated runtime stack.

It complements the local host-run harness:

- `/Users/chranama/career/inference-serving-gateway/proof/run_local_stack.sh`

The local-stack harness uses:

- Docker Compose for infra and observability services
- host-run backend, worker, and gateway processes

The kind harness uses:

- a local `kind` cluster
- Kubernetes deployments for the backend API, async worker, and gateway
- in-cluster Postgres and Redis from the backend repo's Kubernetes base
- port-forwarded proof runs against the deployed services

Canonical entrypoint:

```bash
proof/run_kind_stack.sh up
```

Supporting commands:

```bash
proof/run_kind_stack.sh status
proof/run_kind_stack.sh proof
proof/run_kind_stack.sh down
```

## Images

The kind workflow builds and loads two local images:

- `llm-server:dev`
- `inference-serving-gateway:dev`

## Canonical Kubernetes resources

Backend overlay:

- `/Users/chranama/career/llm-extraction-platform/deploy/k8s/overlays/local-observability-kind`

Integrated add-on kustomization:

- `/Users/chranama/career/inference-serving-gateway/deploy/k8s/local-kind-stack`

## Runtime contract

Namespace:

- `llm`

Backend API:

- deployment name: `api`
- service name: `api`
- backend model profile: `observability-proof`
- edge mode: `behind_gateway`

Async worker:

- deployment name: `extract-worker`
- image: `llm-server:dev`
- runs `python -m llm_server.worker.extract_jobs --poll-timeout-seconds 1`

Gateway:

- deployment name: `gateway`
- service name: `gateway`
- upstream target: `http://api:8000`

Seed job:

- job name: `seed-proof-keys`
- ensures:
  - `proof-user-key`
  - `proof-admin-key`

## Proof contract

The kind proof path port-forwards:

- `svc/api` to a local backend port
- `svc/gateway` to a local gateway port

Then it runs:

- `/Users/chranama/career/inference-serving-gateway/proof/generate_llm_extraction_platform_observability_pack.sh`

with:

- direct backend/admin access via the port-forwarded API service
- gateway routing exercised via the port-forwarded gateway service

This keeps the proof pack semantics aligned with Phase 1 and Phase 1.5 while validating the actual in-cluster deployment shape.
