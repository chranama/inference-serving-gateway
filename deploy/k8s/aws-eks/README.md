# AWS EKS Add-On Path

This directory is the canonical integrated Kubernetes path for AWS/EKS-specific add-ons owned by the gateway repo.

Planning reference:

- `/Users/chranama/career/job-search/audit/2026-03-28__phase2-3-aws-deployment-slice-implementation-plan.md`
- `/Users/chranama/career/inference-serving-gateway/docs/aws-deployment-contract.md`

At `2.3.1`, this path is still scaffold-only, but the scaffold now carries contract obligations rather than only placeholders.

## Contract Responsibilities

This path should eventually hold the integrated AWS/EKS manifests or notes that preserve:

- `ALB`-first ingress with no custom-domain requirement
- gateway-visible smoke, inspect, and rollback inputs
- `CloudWatch Logs` as the bounded cloud-log surface
- correlation continuity for:
  - `request_id`
  - `trace_id`
  - `job_id`
- explicit secrets and config materialization assumptions
- the bounded proof-environment posture:
  - one dev environment
  - session-driven lifecycle
  - reviewer-visible rollback or teardown path

## Minimum 2.3.1 Workflow Inputs

Even before manifests land, this path should make room for the inputs the first AWS proof will need:

- the `ALB` DNS endpoint or ingress target
- one canonical sync smoke request
- one canonical async submit and completion proof
- one correlated log-inspection path in `CloudWatch Logs`
- one correlated trace view in Jaeger
- one gateway or backend metrics view that can be read against the seeded thresholds
- one usage or rough-cost snapshot tied to the bounded `api_key` scope

## Expected Future Contents

- gateway deployment/service adjustments for AWS
- ingress resources
- bounded observability add-ons that belong to the integrated stack rather than the backend overlay alone
- bounded cloud log-path assumptions for correlated inspection
- smoke and inspection workflow assumptions for the gateway-led AWS slice
- config/secrets materialization assumptions that belong to the integrated path
- notes about how gateway-visible rejects surface quota, admission, or fairness controls from the backend side

## 2.3.1 Done Means

This path does not need a full deployable manifest set yet.
It does need to stop hiding which operator workflow and proof inputs later slices are expected to preserve.
