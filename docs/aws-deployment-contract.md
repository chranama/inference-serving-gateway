# AWS Deployment Contract

This document defines the active AWS deployment contract for the integrated
`inference-serving-gateway` plus `llm-extraction-platform` stack.

The contract is intentionally bounded. Its purpose is to prove that the joint
system can leave local Docker and `kind` while preserving the same service
boundaries, request identity, runtime inspection, and teardown discipline.

## Status

Current AWS work is in progress.

Implemented surfaces:

- AWS-target image publication workflows for both repositories.
- Terraform substrate path in this repository at `deploy/aws/terraform/`.
- AWS/EKS gateway overlay path in this repository at `deploy/k8s/aws-eks/`.
- Backend-specific AWS overlay path in the backend repository at
  `deploy/k8s/overlays/aws-eks/`.
- Backend vLLM overlay path in the backend repository at
  `deploy/k8s/overlays/aws-eks-vllm/`.
- Joint AWS harness at `proof/run_aws_stack.sh`.
- Harness workflow selection with `AWS_WORKFLOW=fake` and `AWS_WORKFLOW=vllm`.

Still pending:

- AWS image publication into ECR;
- AWS Load Balancer Controller and CloudWatch Observability add-on execution;
- deployed fake-backend smoke, inspection, rollback, and teardown proof artifacts;
- deployed vLLM smoke, inspection, rollback, and teardown proof artifacts.

## Deployment Objective

The first AWS slice should demonstrate a production-shaped but cost-bounded
deployment:

```text
ALB
  -> inference-serving-gateway
      -> llm-extraction-platform API
      -> llm-extraction-platform async worker
      -> optional vLLM model runtime
      -> RDS PostgreSQL
      -> ElastiCache Redis
```

The gateway is the public ingress boundary. The backend API and worker are
internal runtime services behind that boundary.

The contract promotes two AWS workflows:

| Workflow | Runtime Target | What It Proves |
|---|---|---|
| `AWS_WORKFLOW=fake` | Deterministic in-process backend | Cloud deployment, public ingress, service boundaries, managed RDS/Redis, request identity, observability, and teardown |
| `AWS_WORKFLOW=vllm` | Separate OpenAI-compatible vLLM Deployment on a GPU node group | The same cloud stack plus live model-serving integration, GPU scheduling, and model-runtime inspection |

## Non-Goals

The first AWS slice does not need to prove:

- multi-environment promotion;
- custom domain, Route 53, or WAF;
- production HA or disaster recovery;
- autoscaling maturity;
- full GitOps release management;
- a large secrets-management control plane;
- a separate billing, chargeback, or SLO platform.

Those are valid future concerns, but they would make the first AWS proof less
legible.

## Canonical Environment

| Field | Contract |
|---|---|
| Environment | `dev` |
| Region | `us-east-1` |
| Cluster | `llm-runtime-dev` |
| Namespace | `llm` |
| Image architecture | `linux/amd64` |
| Gateway ECR repository | `inference-serving-gateway` |
| Backend ECR repository | `llm-server` |
| Model runtime image | `vllm/vllm-openai` for `AWS_WORKFLOW=vllm` |
| Public ingress | ALB in front of the gateway |
| Managed database | RDS PostgreSQL |
| Managed queue/cache | ElastiCache Redis |
| Log surface | CloudWatch Logs |
| Trace surface | In-cluster Jaeger for the first slice |
| Metrics surface | In-cluster Prometheus/Grafana for the first slice |

Use the ALB DNS name first. A custom domain is explicitly out of scope for the
first slice.

## AWS Component Inventory

The first deployment slice uses this AWS component set:

| Component | What It Does | First-Slice Posture |
|---|---|---|
| VPC | Provides the isolated AWS network where the cluster, ingress, and managed data services live | Terraform-owned, single `dev` VPC |
| Public subnets | Host internet-reachable resources such as ALB, and bounded node placement for the no-NAT first slice | Tagged for Kubernetes external load balancers |
| Private subnets | Provide non-public subnet groups for managed data services | Used for RDS and ElastiCache |
| Internet Gateway and route tables | Connect public subnets to the internet and define subnet routing behavior | Terraform-owned |
| NAT Gateway | Would let private subnet workloads reach the internet without public addresses | Disabled by default |
| Security groups | Act as AWS firewall rules for ingress, egress, and managed data access | Terraform-owned, scoped to the bounded VPC |
| ECR | Stores proof-session container images that EKS pulls at deployment time | Terraform-owned `inference-serving-gateway` and `llm-server` repositories, deleted on full teardown |
| IAM | Defines AWS permissions for EKS, worker nodes, and GitHub Actions image publication | Terraform-owned, OIDC-based publish path |
| EKS | Runs the Kubernetes control plane for the joint runtime | One `dev` cluster |
| EC2 managed node group | Supplies the worker-node compute where Kubernetes pods run | One bounded node group |
| EC2 GPU managed node group | Supplies accelerated compute for the live vLLM workflow | Disabled by default; enabled only for `AWS_WORKFLOW=vllm` |
| EC2 `Running On-Demand G and VT instances` quota | Allows GPU-family EC2 capacity such as `g6.xlarge` to launch in the selected region | Must be at least 4 vCPUs for the promoted one-node vLLM workflow |
| Application Load Balancer | Receives public HTTP traffic and forwards it to the gateway service | ALB DNS name first, no custom domain required |
| AWS Load Balancer Controller | Watches Kubernetes ingress resources and creates/manages AWS load balancers | Required before ALB ingress is deployable |
| RDS PostgreSQL | Provides the managed relational database used by the backend | Managed replacement for in-cluster Postgres |
| ElastiCache Redis | Provides managed Redis for async queue/state support | Managed replacement for in-cluster Redis |
| Secrets Manager | Stores long-lived runtime secrets outside source control and manifests | Small bounded secret set |
| CloudWatch Logs | Collects cloud-side logs for gateway, backend, and worker inspection | Required cloud log surface |

In-cluster OTel Collector, Jaeger, Prometheus, and Grafana are part of the AWS
runtime proof, but they are not AWS managed services in the first slice.

The vLLM image is intentionally separate from the backend API image. The backend
API image should remain a slim application image; live model-serving weight
belongs to the model-runtime Deployment in the vLLM workflow.

The vLLM workflow also depends on the regional EC2 quota named `Running
On-Demand G and VT instances`. The first promoted target uses one `g6.xlarge`
node, so the quota must be at least 4 vCPUs in `us-east-1`. The AWS harness
checks this during `AWS_WORKFLOW=vllm proof/run_aws_stack.sh preflight` before
Terraform is applied.

Explicitly excluded from the first slice unless added later by contract:

- Route 53;
- ACM-managed custom-domain TLS;
- WAF;
- multi-AZ HA posture;
- AWS billing or chargeback services;
- always-on NAT Gateway.

## Repository Ownership

This repository owns the integrated AWS front door:

- Terraform root and environment contract;
- gateway AWS image publication;
- gateway ingress and AWS/EKS add-on path;
- joint AWS runbook/proof harness;
- reviewer-facing deployment walkthrough.

The backend repository owns backend-specific AWS participation:

- backend AWS image publication;
- backend API and worker overlay details;
- backend runtime config and migrations;
- backend proof expectations for sync extract, async extract, usage, and traces.

Backend-side contract:

- `/Users/chranama/career/llm-extraction-platform/docs/aws-deployment-contract.md`

## Infrastructure Contract

Terraform is the source of truth for the AWS substrate.

Canonical root:

- `deploy/aws/terraform/`

Expected layout:

```text
deploy/aws/terraform/
  modules/
    network/
    ecr/
    iam/
    eks/
    data/
  environments/
    dev/
```

The current substrate target includes:

- VPC with DNS support;
- public subnets for ALB and bounded node placement;
- private subnets for managed data subnet groups;
- optional NAT Gateway disabled by default;
- ephemeral ECR repositories for gateway and backend images;
- EKS cluster and one managed node group;
- optional GPU managed node group for live vLLM model serving;
- RDS PostgreSQL;
- ElastiCache Redis;
- GitHub Actions OIDC role for ECR image publication.

The first AWS slice should remain teardown-friendly. `terraform destroy` is an
acceptable rollback/cleanup path for the bounded `dev` environment.

## Cost Guardrails

The first slice is designed for proof sessions, not continuous uptime.

Required guardrails:

- one region;
- one environment;
- one bounded node group;
- optional one-node GPU group only for the vLLM workflow;
- no custom domain in the first slice;
- no WAF in the first slice;
- NAT Gateway disabled unless a validated constraint requires it;
- small managed data instances;
- ECR lifecycle policies as a fallback if a session is not destroyed promptly;
- explicit full teardown path that deletes the ECR repositories and images.

Do not add AWS services only because they look production-like. Add them only
when they materially improve the reviewer-facing deployment proof.

## Image Publication Contract

GitHub Actions owns AWS-target image publication during a live proof session.
Terraform owns ECR repository creation and deletion.

Gateway workflow:

- `.github/workflows/aws-image-publish.yml`

Backend workflow:

- `/Users/chranama/career/llm-extraction-platform/.github/workflows/aws-image-publish.yml`

Publication rules:

- platform: `linux/amd64`;
- target: Terraform-created ephemeral ECR repository;
- immutable tag: `git-<sha>`;
- proof-session tag: `run-<github_run_id>`;
- session moving tag: `aws-dev-latest`;
- deploy manifests should prefer image digests or immutable `git-<sha>` tags.

GitHub Actions configuration:

- `vars.AWS_ROLE_TO_ASSUME` is required to publish;
- `vars.AWS_REGION` defaults to `us-east-1`;
- publish workflows are manual and run after `terraform-apply`;
- publish workflows refuse to push unless the target ECR repository has
  `ephemeral=true` and `managed_by=terraform` tags.

The publish workflows must not create ECR repositories. If the repository is
missing, the correct operator action is to apply the Terraform substrate first.
At the end of the proof session, `terraform destroy` removes the repositories
and the pushed images.

Local and `kind` workflows keep their local image tags. AWS deployment should not
consume workstation-local images.

Image responsibilities:

| Image | Owner | Used By | Weight Policy |
|---|---|---|---|
| `inference-serving-gateway` | Gateway repository | Gateway Deployment | Small Go edge image pushed into ephemeral ECR |
| `llm-server` | Backend repository | Backend API, worker, migrations, seed jobs | Slim Python application image pushed into ephemeral ECR; no default Torch/Transformers/llama.cpp stack |
| `vllm/vllm-openai` | vLLM project | Optional vLLM model-runtime Deployment | Large model-serving image, used only by `AWS_WORKFLOW=vllm` |

The application images should stay deployable on the bounded CPU node group. GPU
and model-serving dependencies are isolated to the optional vLLM workflow.

## Kubernetes Runtime Contract

The AWS workload topology should be a cloud deployment of the proven joint
Kubernetes shape:

- gateway Deployment and Service;
- gateway Ingress through AWS ALB;
- backend API Deployment and internal Service;
- backend worker Deployment;
- optional vLLM Deployment and Service for `AWS_WORKFLOW=vllm`;
- database migration Job;
- proof-key or bounded usage seed Job;
- OTel Collector;
- Jaeger;
- Prometheus/Grafana, if kept in-cluster for the first slice.

The backend API should not be the public ingress service. The gateway owns the
public route surface.

The external route contract remains:

- `POST /v1/extract`;
- `POST /v1/extract/jobs`;
- `GET /v1/extract/jobs/{job_id}`;
- required health/readiness endpoints.

`/v1/generate` is not promoted as a gateway-supported AWS route unless the
gateway explicitly adds that route later.

## Secrets And Config Contract

The first AWS slice must make secrets and runtime config explicit.

Required runtime inputs:

- backend API key and admin key;
- database connection details for RDS;
- Redis connection details for ElastiCache;
- gateway upstream base URL;
- OTel collector endpoint;
- model/config profile;
- optional `HF_TOKEN` only when the selected vLLM model requires Hugging Face
  authentication.

Preferred managed source:

- AWS Secrets Manager.

Acceptable first-slice materialization:

- Terraform-owned Kubernetes Secrets, if the source and values are explicitly
  documented and bounded.

The contract goal is not a large secrets platform. The goal is to avoid a cloud
deployment where credentials appear by implication.

## Runtime Identity Contract

Application identity remains authoritative across local, `kind`, and AWS:

- `request_id`;
- `trace_id`;
- `job_id`.

Do not replace these with AWS-native identifiers. AWS log and trace surfaces
should preserve them so one proof request can be followed across gateway,
backend, and worker.

## Observability Contract

The AWS slice must preserve the current inspection model:

- gateway logs;
- backend API logs;
- worker logs;
- vLLM logs and metrics for `AWS_WORKFLOW=vllm`;
- gateway metrics;
- backend metrics;
- OTel traces;
- admin/runtime trace inspection where available.

CloudWatch Logs is the bounded cloud log surface for the first slice. In-cluster
Jaeger and Prometheus/Grafana remain acceptable for the first AWS proof if they
are documented as bounded, session-oriented components.

Required correlation fields:

- `request_id`;
- `trace_id`;
- `job_id` for async work.

## Proof Workflow Contract

The first AWS proof should generate one bounded evidence pack.

Minimum workflow:

1. `apply`
   - provision or confirm Terraform substrate;
   - enable the GPU node group when `AWS_WORKFLOW=vllm`;
   - deploy AWS/EKS manifests;
   - install the NVIDIA device plugin when `AWS_WORKFLOW=vllm`;
   - wait for gateway, backend, worker, optional vLLM, and data dependencies.
2. `smoke`
   - call gateway health through the ALB path;
   - run one sync extract through ALB;
   - submit one async extract job through ALB;
   - poll async job completion through ALB.
3. `inspect`
   - capture CloudWatch log queries or log excerpts;
   - capture gateway and backend metrics;
   - capture vLLM logs and metrics when `AWS_WORKFLOW=vllm`;
   - capture one trace view or exported trace payload;
   - capture one usage or quota/cost snapshot tied to the proof key.
4. `rollback-or-teardown`
   - document image/config rollback if used;
   - otherwise run and document `terraform destroy`.

The proof pack should make a reviewer able to answer:

- did ingress reach the gateway?
- did the gateway reach the backend?
- did the worker complete async work?
- did managed Postgres and Redis participate?
- did vLLM become reachable by the backend when the live workflow is selected?
- can one request be followed through logs, metrics, and traces?
- what operator decision would cause rollback or teardown?

## Usage, Quota, And Cost Contract

The first bounded usage scope is:

- `api_key`.

Minimum metering surfaces:

- backend usage endpoints;
- inference logs with token/latency data;
- proof artifacts;
- one documented rough-cost note.

The first cloud slice must include one visible spend or fairness control. The
preferred implementation is to reuse existing backend API-key quota or admission
behavior and surface rejects through gateway/backend logs, metrics, or proof
artifacts.

Raw API keys must not become default Prometheus labels.

## Health And Rollback Criteria

The first rollback trigger can remain manual, but it must be legible.

Reviewer-visible rollback or teardown triggers:

- canonical gateway health check fails;
- canonical sync extract fails;
- canonical async proof fails to complete within the bounded timeout;
- request identity is not visible across logs/traces;
- sync p95 latency exceeds `2x` the recent bounded baseline for `15m`;
- rough request cost changes materially without an intentional runtime change.

Seeded thresholds for the first slice:

- sync extract success: `100%` on the canonical smoke path;
- contract-valid extract rate: `>= 98%` over the bounded rollout window;
- async submit acceptance: `>= 99%` over the bounded rollout window;
- async completion before timeout: `>= 95%` over the bounded rollout window.

These thresholds are decision seeds, not a claim of mature production SLO
automation.

## Acceptance Criteria

The AWS deployment contract is satisfied when:

- Terraform can provision the bounded substrate;
- both repos can publish AWS-target images to Terraform-owned ephemeral ECR;
- Kubernetes manifests deploy gateway, backend API, and worker on EKS;
- the ALB reaches the gateway;
- the gateway reaches the backend;
- backend and worker use RDS and ElastiCache;
- one sync and one async proof run succeed through the ALB;
- logs, metrics, and traces remain inspectable;
- one usage/quota/cost snapshot exists for the proof key;
- workload deletion and full substrate teardown are documented and exercised;
- docs and proof artifacts match the actual deployed shape.

For the vLLM workflow, satisfaction also requires:

- Terraform can provision the optional GPU node group;
- the NVIDIA device plugin is installed;
- the vLLM Deployment becomes ready on a GPU node;
- backend extract calls reach the vLLM OpenAI-compatible endpoint;
- vLLM logs and metrics are captured in the proof artifact set.

## Implementation Gaps To Close Next

1. Apply the Terraform substrate for `AWS_WORKFLOW=fake`.
2. Publish gateway and backend images into the ephemeral ECR repositories.
3. Run the joint AWS harness through deploy, smoke, inspect, and full teardown for
   `AWS_WORKFLOW=fake`.
4. Enable the GPU node group and install the NVIDIA device plugin.
5. Run deploy, smoke, inspect, and full teardown for `AWS_WORKFLOW=vllm`.
