# AWS Deployment Contract

This document defines the canonical AWS deployment contract for the integrated `inference-serving-gateway` + `llm-extraction-platform` stack.

Primary planning reference:

- `/Users/chranama/career/job-search/audit/2026-03-28__phase2-3-aws-deployment-slice-implementation-plan.md`

Cost audit reference:

- `/Users/chranama/career/job-search/audit/2026-03-28__phase2-3-aws-cost-audit.md`

Phase 2.2.9 runtime contract references:

- [Runtime Decision Contract](runtime-decision-contract.md)
- `/Users/chranama/career/llm-extraction-platform/docs/runtime-quality-scorecard.md`

## Purpose

The AWS slice exists to prove that the integrated runtime stack is:

- not only locally integrated
- not only deployable to `kind`
- but also deployable to a real cloud environment through a bounded, reviewer-friendly infrastructure path

This contract is intentionally:

- Kubernetes-shaped
- Terraform-owned
- cost-bounded
- operator-inspectable

## Canonical First Environment

Environment name:

- `dev`

Primary region:

- `us-east-1`

AWS-target image architecture:

- `linux/amd64`

Kubernetes namespace:

- `llm`

Gateway ingress path:

- `ALB` in front of the gateway
- use the ALB DNS name first
- no custom domain required in the first slice

Bounded cloud log path:

- `CloudWatch Logs` is the default cloud log surface for:
  - gateway
  - backend
  - worker
- log inspection should preserve correlation by:
  - `request_id`
  - `trace_id`
  - `job_id`

Canonical operator workflow shape:

- `smoke`
  - check ingress health and one sync request against the `ALB`
- `inspect`
  - follow one sync or async run through `CloudWatch Logs`, metrics, and Jaeger traces
- `rollback or teardown`
  - if the slice is unhealthy, either return to the prior image/config revision or destroy the bounded environment

At `2.3.1`, this is a contract-level workflow shape, not a fully implemented runbook yet.

Current seeded health and decision contract:

- sync extract success rate:
  - `>= 99%` over the `1h` rollout window
  - `100%` on the canonical smoke path
- sync extract p95 latency:
  - `<= 2.0s` over the `5m` live-operator window on the bounded observability-proof profile
- contract-valid extract rate:
  - `>= 98%` over the `1h` rollout window
- async submit acceptance rate:
  - `>= 99%` over the `1h` rollout window
- async completion-before-timeout rate:
  - `>= 95%` over the `1h` rollout window
- keep the first rollback trigger manual and reviewer-visible
- reuse the existing metrics, logs, traces, and runbook surfaces instead of adding a separate SLO control plane

## 2.3.1 Runtime, Quality, And Usage Contract

The AWS slice is allowed to look cloud-specific.
It is not allowed to invent a different runtime-decision model than the one already seeded in `Phase 2.2.9`.

Current runtime-quality signals that are allowed to influence route, prompt, provider, repair, or policy decisions:

- `extract_contract_pass_rate`
- `structured_output_invalid_rate`
- `repair_attempt_rate`
- `repair_success_rate`
- `policy_rejection_rate`
- `async_completion_before_timeout_rate`
- `rough_request_cost_usd`

These are backend-derived signals, but the integrated AWS slice must make them inspectable through one gateway-led proof workflow.

Current bounded usage and metering contract:

- the first cloud-slice usage scope remains:
  - `api_key`
- the first metering surfaces remain:
  - `GET /v1/me/usage`
  - `GET /v1/admin/usage`
  - inference logs with token and latency data
  - reviewer-visible proof artifacts and runbook notes
- raw `api_key` values are acceptable in DB-backed admin or proof surfaces
- raw `api_key` values are not acceptable default Prometheus labels

Current minimum spend and fairness control:

- the first AWS slice must keep one explicit quota, budget, or admission-control rule that protects the bounded proof environment
- the preferred first implementation is:
  - reuse the existing backend API-key quota or admission surfaces
  - make gateway-visible rejects or throttles inspectable in logs, metrics, or proof artifacts
- this does not require a billing subsystem or a separate tenant-governance service

Current rough cost-attribution contract:

- derive rough request or run cost from:
  - inference logs
  - token counts
  - usage endpoints
  - provider pricing assumptions where available
- do not block `2.3.1` on AWS CUR, Athena, or chargeback machinery

## 2.3.1 Proof And Rollback Evidence Contract

The first AWS slice should be reviewable through one bounded evidence pack.

Minimum evidence shape:

- one canonical sync smoke request through the `ALB`
- one canonical async submit and completion check through the `ALB`
- one correlated log path in `CloudWatch Logs`
- one correlated trace view in Jaeger
- one gateway metrics snapshot and one backend metrics snapshot that can be read against the seeded thresholds
- one usage or cost snapshot tied back to the bounded `api_key` usage scope

Manual rollback or teardown remains acceptable for the first slice, but the trigger should be legible.

Reviewer-visible rollback or escalation triggers:

- canonical sync smoke fails
- canonical async proof fails to complete acceptably
- seeded sync success rate falls below target after the current change
- seeded contract-valid rate falls below target after the current change
- sync p95 latency exceeds `2x` the recent bounded baseline for `15m`
- rough request cost jumps materially without an intentional runtime or policy change

## Naming Contract

Cluster name:

- `llm-runtime-dev`

Gateway ECR repository:

- `inference-serving-gateway`

Backend ECR repository:

- `llm-server`

These names are meant to stay stable unless there is a strong reason to change them.

## 2.3.2 AWS-Target Image Publish Contract

GitHub Actions is the canonical owner of AWS-target image publication for the first cloud slice.

Canonical workflow path in this repo:

- `/Users/chranama/career/inference-serving-gateway/.github/workflows/aws-image-publish.yml`

Current publication rules:

- publish platform:
  - `linux/amd64`
- publish target:
  - `ECR`
- canonical moving tags on the default branch:
  - `main`
  - `aws-dev-latest`
- canonical immutable tag:
  - `git-<sha>`
- later deploy steps should prefer:
  - image digest
  - or the immutable `git-<sha>` tag
- local dev and `kind` workflows should continue using their own local image tags and should not be treated as the AWS publication path

GitHub Actions credential contract:

- `vars.AWS_ROLE_TO_ASSUME` is the required GitHub-side input for OIDC-based publication
- `vars.AWS_REGION` is optional and defaults to `us-east-1`

The goal of `2.3.2` is not release management in the abstract.
The goal is to ensure the AWS slice consumes reproducible CI-built images rather than workstation-local tags.

## Cost Guardrails

The first AWS slice is intentionally constrained:

- one region
- one environment
- one bounded node group
- single-AZ first where practical
- `NAT Gateway` disabled by default
- environment intended for proof/test sessions, not 24/7 uptime

That means:

- the environment should be easy to `terraform apply`
- the environment should be easy to `terraform destroy`
- the first implementation should not add AWS services that materially increase cost without materially improving the proof

## IAM, Secrets, And Config Ownership

The first AWS slice should have a small but explicit identity and secrets/config model.

Terraform provisioning identity:

- a human or automation identity with permission to manage the bounded AWS substrate

GitHub Actions identity:

- one explicit credential or role-assumption path for:
  - publishing AWS-target images to `ECR`
  - later deploy-support steps if they are added

Runtime workload identity:

- cluster add-ons and workloads should use the smallest practical AWS permissions needed for the first slice
- permissions should be documented even if the initial implementation is intentionally minimal

Secrets/config contract:

- long-lived secrets should have one canonical managed source
- `Secrets Manager` is the default managed secret store for the first slice
- in-cluster materialization is acceptable for the first slice if:
  - it is Terraform-owned
  - it is explicit
  - it is documented

The point of this contract is not to build a large secrets platform.
The point is to avoid an AWS slice that reads as “credentials appear by magic.”

## Repository Ownership

The gateway repo is the front door for the integrated AWS slice.

Canonical AWS roots in this repo:

- `/Users/chranama/career/inference-serving-gateway/deploy/aws/terraform/`
- `/Users/chranama/career/inference-serving-gateway/deploy/k8s/aws-eks/`

The backend repo owns backend-specific overlays and backend-side AWS contract notes.

Backend-side reference:

- `/Users/chranama/career/llm-extraction-platform/docs/aws-deployment-contract.md`

## Current Terraform Layout Contract

Terraform root:

- `/Users/chranama/career/inference-serving-gateway/deploy/aws/terraform/`

Expected layout:

```text
deploy/aws/terraform/
  modules/
    network/
    ecr/
    eks/
    data/
    iam/
  environments/
    dev/
```

At `2.3.1`, this layout is a contract and scaffold, not a full infrastructure implementation yet.

The intent of the first module set is:

- `network`
  - bounded VPC and subnet contract
- `ecr`
  - image repository contract
- `eks`
  - cluster and node-group contract
- `data`
  - managed Postgres and Redis contract
- `iam`
  - provisioning and workload-identity contract

## Current Kubernetes Layout Contract

Integrated AWS add-ons path:

- `/Users/chranama/career/inference-serving-gateway/deploy/k8s/aws-eks/`

This is the AWS counterpart to:

- `/Users/chranama/career/inference-serving-gateway/deploy/k8s/local-kind-stack/`

The AWS/EKS add-on path is expected to become the home for:

- ingress resources
- observability add-ons
- bounded cloud-log wiring assumptions
- config/secrets materialization assumptions for the integrated stack

## What Is Explicitly Out Of Scope For The First AWS Slice

The first AWS slice should not require:

- multi-environment rollout
- custom domain / Route 53
- WAF
- multi-AZ HA posture
- always-on NAT
- a large secrets-management control plane
- full GitOps promotion machinery

Those can be added later if they become necessary.

## 2.3.1 Acceptance Notes

`Phase 2.3.1` should now be treated as complete only if these contract-level decisions are visible:

- the smoke, inspection, and rollback/teardown workflow shape
- the bounded cloud log-inspection path
- the IAM, secrets, and config ownership model
- the seeded sync and async `SLI` / `SLO` view with named thresholds for:
  - sync success
  - sync p95 latency
  - contract-valid extract rate
  - async submit acceptance
  - async completion-before-timeout
- the first rollback or escalation thresholds tied to those seeds
- the operational quality signals that are allowed to influence runtime choice
- the first bounded usage scope, minimal metering surface, and basic spend or fairness control
- the rough cost-attribution path
- the minimum proof pack needed to justify keep, rollback, or teardown decisions

Those do not require a deployed stack yet.
They do require the contract docs to stop leaving these concerns implicit.
