# AWS Deployment Contract

This document defines the active AWS deployment contract for the integrated
`inference-serving-gateway` plus `llm-extraction-platform` stack.

The contract is intentionally bounded. Its purpose is to prove that the joint
system can leave local Docker and `kind` while preserving the same service
boundaries, request identity, runtime inspection, and teardown discipline.

## Status

Current AWS work is in progress.

Implemented or scaffolded surfaces:

- AWS-target image publication workflows for both repositories.
- Terraform substrate path in this repository at `deploy/aws/terraform/`.
- AWS/EKS add-on path in this repository at `deploy/k8s/aws-eks/`.
- Backend-specific AWS overlay path in the backend repository at
  `deploy/k8s/overlays/aws-eks/`.

Still pending:

- deployable AWS/EKS Kubernetes manifests;
- AWS ingress, secrets/config materialization, and cloud log wiring;
- deployed smoke, inspection, rollback, and teardown proof artifacts.

## Deployment Objective

The first AWS slice should demonstrate a production-shaped but cost-bounded
deployment:

```text
ALB
  -> inference-serving-gateway
      -> llm-extraction-platform API
      -> llm-extraction-platform async worker
      -> RDS PostgreSQL
      -> ElastiCache Redis
```

The gateway is the public ingress boundary. The backend API and worker are
internal runtime services behind that boundary.

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
| Public ingress | ALB in front of the gateway |
| Managed database | RDS PostgreSQL |
| Managed queue/cache | ElastiCache Redis |
| Log surface | CloudWatch Logs |
| Trace surface | In-cluster Jaeger for the first slice |
| Metrics surface | In-cluster Prometheus/Grafana for the first slice |

Use the ALB DNS name first. A custom domain is explicitly out of scope for the
first slice.

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
- ECR repositories for gateway and backend images;
- EKS cluster and one managed node group;
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
- no custom domain in the first slice;
- no WAF in the first slice;
- NAT Gateway disabled unless a validated constraint requires it;
- small managed data instances;
- ECR lifecycle policies;
- explicit teardown path.

Do not add AWS services only because they look production-like. Add them only
when they materially improve the reviewer-facing deployment proof.

## Image Publication Contract

GitHub Actions owns AWS-target image publication.

Gateway workflow:

- `.github/workflows/aws-image-publish.yml`

Backend workflow:

- `/Users/chranama/career/llm-extraction-platform/.github/workflows/aws-image-publish.yml`

Publication rules:

- platform: `linux/amd64`;
- target: ECR;
- immutable tag: `git-<sha>`;
- dev moving tags: `main`, `aws-dev-latest`;
- deploy manifests should prefer image digests or immutable `git-<sha>` tags.

GitHub Actions configuration:

- `vars.AWS_ROLE_TO_ASSUME` is required to publish;
- `vars.AWS_REGION` defaults to `us-east-1`.

Local and `kind` workflows keep their local image tags. AWS deployment should not
consume workstation-local images.

## Kubernetes Runtime Contract

The AWS workload topology should be a cloud deployment of the proven joint
Kubernetes shape:

- gateway Deployment and Service;
- gateway Ingress through AWS ALB;
- backend API Deployment and internal Service;
- backend worker Deployment;
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
- any model-provider secrets if a live model backend is later promoted.

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
   - deploy AWS/EKS manifests;
   - wait for gateway, backend, worker, and data dependencies.
2. `smoke`
   - call gateway health through the ALB path;
   - run one sync extract through ALB;
   - submit one async extract job through ALB;
   - poll async job completion through ALB.
3. `inspect`
   - capture CloudWatch log queries or log excerpts;
   - capture gateway and backend metrics;
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
- both repos can publish AWS-target images to ECR;
- Kubernetes manifests deploy gateway, backend API, and worker on EKS;
- the ALB reaches the gateway;
- the gateway reaches the backend;
- backend and worker use RDS and ElastiCache;
- one sync and one async proof run succeed through the ALB;
- logs, metrics, and traces remain inspectable;
- one usage/quota/cost snapshot exists for the proof key;
- rollback or teardown is documented and exercised;
- docs and proof artifacts match the actual deployed shape.

## Implementation Gaps To Close Next

1. Commit or finish the AWS image-publish workflows.
2. Validate and commit the Terraform substrate.
3. Add AWS/EKS manifests for gateway ingress and observability add-ons.
4. Add backend AWS overlay manifests for API, worker, migration, config, and
   managed data wiring.
5. Add a joint AWS proof harness that captures ALB smoke, async completion,
   logs, metrics, traces, usage, and teardown evidence.
