# AWS EKS Add-On Path

This directory is the canonical integrated Kubernetes path for AWS/EKS-specific add-ons owned by the gateway repo.

Planning reference:

- `/Users/chranama/career/job-search/audit/2026-03-28__phase2-3-aws-deployment-slice-implementation-plan.md`
- `/Users/chranama/career/inference-serving-gateway/docs/aws-deployment-contract.md`

This path now carries the gateway-owned AWS/EKS manifests for the first bounded
AWS slice. The backend-owned AWS overlay lives in the sibling
`llm-extraction-platform` repository.

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

## Contents

- `kustomization.yaml`: gateway-owned AWS overlay.
- `gateway-ingress.yaml`: ALB ingress entry point.
- `gateway-patch.yaml`: AWS runtime settings for gateway routing, admission, and tracing.
- `observability-patch.yaml`: bounded resource settings for in-cluster OTel and Jaeger.

The AWS runbook renders this path together with the backend overlay:

- `/Users/chranama/career/inference-serving-gateway/docs/aws-runbook.md`
