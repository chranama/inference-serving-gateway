# AWS Terraform Scaffold

This directory is the canonical Terraform root for the bounded AWS deployment slice.

Planning reference:

- `/Users/chranama/career/job-search/audit/2026-03-28__phase2-3-aws-deployment-slice-implementation-plan.md`

Gateway-side AWS contract:

- `/Users/chranama/career/inference-serving-gateway/docs/aws-deployment-contract.md`

## Purpose

At `2.3.1`, this directory establishes:

- the canonical Terraform layout
- the canonical `dev` environment contract
- the cost guardrails that will shape later resource implementation

This is a scaffold, not a full infrastructure implementation yet.

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
