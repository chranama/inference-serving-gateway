# AWS Terraform Scaffold

This directory is the canonical Terraform root for the bounded AWS deployment slice.

Planning reference:

- `/Users/chranama/career/job-search/audit/2026-03-28__phase2-3-aws-deployment-slice-implementation-plan.md`

Gateway-side AWS contract:

- `/Users/chranama/career/inference-serving-gateway/docs/aws-deployment-contract.md`

## Purpose

At `2.3.3`, this directory now establishes:

- the canonical Terraform layout
- the canonical `dev` environment contract
- the cost guardrails that will shape later resource implementation
- the IAM and identity boundary where the first AWS slice will be explained
- the exported runtime, usage, and rollback seeds that later slices should obey
- the bounded AWS substrate itself:
  - VPC and subnets
  - ECR repositories
  - EKS cluster and node group
  - managed Postgres
  - managed Redis

The substrate is now implemented in Terraform.
Later `2.3.x` slices still own add-ons, secrets materialization, ingress, and application rollout.

## Layout

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

## First-Slice Cost Rules

The Terraform path is expected to preserve:

- `us-east-1`
- `dev`
- one bounded node group
- single-AZ first where practical
- `NAT Gateway` disabled by default
- environment designed for teardown after proof sessions

The Terraform scaffold should also preserve the cheaper interpretation of the newer runtime requirements:

- keep request-level metering and rough cost attribution in the runtime and observability plane
- keep quota, fairness, or admission control to one simple bounded rule for the first slice
- avoid new AWS billing or governance services just to satisfy reviewer-facing business fluency

## Contract Outputs And Seeds

The `environments/dev/` scaffold now carries more than naming defaults.

Its exported contract should make visible:

- canonical region, environment, cluster, namespace, and repo names
- one bounded usage scope:
  - `api_key`
- one bounded cloud log surface:
  - `CloudWatch Logs`
- one managed secret source:
  - `Secrets Manager`
- the seeded sync and async `SLI` / `SLO` thresholds reused from `Phase 2.2.9`
- the first rollback and escalation triggers
- the first allowed runtime-quality signals
- the first operator workflow shape:
  - smoke
  - inspect
  - rollback or teardown

These outputs are intentionally documentary at `2.3.1`.
They exist so later Terraform and deploy slices cannot quietly drift away from the agreed runtime contract.

At `2.3.3`, the same `environments/dev/` path also exports the provisioned substrate summaries for:

- network
- ECR
- IAM
- EKS
- managed data

## Contract-Level Responsibilities

At `2.3.1`, this Terraform scaffold is also expected to make room for:

- provisioning identity assumptions
- workload identity assumptions
- managed data contracts
- secrets/config ownership boundaries
- teardown-friendly environment lifecycle

The `iam/` module exists so the first AWS slice does not leave identity and permission concerns implicit, even before the full implementation lands.

Module intent at contract level:

- `network`
  - encode the bounded VPC shape, public ingress posture, and no-`NAT Gateway` default
- `ecr`
  - keep gateway and backend image repository names stable and reviewer-readable
- `eks`
  - encode the bounded cluster and node-group shape plus workload-identity expectations
- `data`
  - encode the managed Postgres and Redis contract without pretending to solve HA yet
- `iam`
  - encode the minimum viable provisioning, publish, and runtime-permission shape

Current implementation note:

- the node group stays bounded and cost-aware
- `RDS` and `ElastiCache` still use managed subnet groups, which is why the default substrate now spans at least two AZs even though the runtime posture is still intentionally small
