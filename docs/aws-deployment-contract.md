# AWS Deployment Contract

This document defines the canonical AWS deployment contract for the integrated `inference-serving-gateway` + `llm-extraction-platform` stack.

Primary planning reference:

- `/Users/chranama/career/job-search/audit/2026-03-28__phase2-3-aws-deployment-slice-implementation-plan.md`

Cost audit reference:

- `/Users/chranama/career/job-search/audit/2026-03-28__phase2-3-aws-cost-audit.md`

## Purpose

The AWS slice exists to prove that the integrated runtime stack is:

- not only locally integrated
- not only deployable to `kind`
- but also deployable to a real cloud environment through a bounded, reviewer-friendly infrastructure path

This contract is intentionally:

- Kubernetes-shaped
- Terraform-owned
- cost-bounded

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

## Naming Contract

Cluster name:

- `llm-runtime-dev`

Gateway ECR repository:

- `inference-serving-gateway`

Backend ECR repository:

- `llm-server`

These names are meant to stay stable unless there is a strong reason to change them.

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

## Current Kubernetes Layout Contract

Integrated AWS add-ons path:

- `/Users/chranama/career/inference-serving-gateway/deploy/k8s/aws-eks/`

This is the AWS counterpart to:

- `/Users/chranama/career/inference-serving-gateway/deploy/k8s/local-kind-stack/`

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
