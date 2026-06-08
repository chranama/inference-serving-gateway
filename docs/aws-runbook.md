# AWS Runbook

This runbook executes the bounded AWS deployment slice for the integrated
`inference-serving-gateway` plus `llm-extraction-platform` stack.

The goal is a short-lived proof deployment:

```text
ALB
  -> inference-serving-gateway
      -> llm-extraction-platform API
      -> llm-extraction-platform worker
      -> RDS PostgreSQL
      -> ElastiCache Redis
```

The first AWS slice proves cloud deployment, service boundaries, managed data,
request identity, and inspection. It uses the deterministic backend profile. It
does not promote live model serving, custom domains, WAF, production HA, or
always-on operation.

## Cost Guardrails

Create billing guardrails before provisioning:

- AWS Budget alerts for actual and forecasted spend.
- Cost Anomaly Detection, if available in the account.
- `dev` only.
- `us-east-1` only.
- NAT Gateway disabled unless a concrete runtime blocker requires it.
- Destroy the stack after the proof session.

The Terraform tags mark resources as:

- `project=llm-runtime-stack`
- `environment=dev`
- `ephemeral=true`

## Required Tools

Local tools:

- `aws`
- `terraform`
- `kubectl`
- `helm`
- `eksctl`
- `jq`
- `curl`
- `python3`

`terraform` and `kubectl` are enough for render validation. Live deployment
requires the AWS CLI, Helm, and eksctl.

## Repository Roles

Gateway repository:

- Terraform substrate.
- AWS gateway overlay and ALB ingress.
- AWS Load Balancer Controller setup.
- Joint AWS harness and proof artifacts.

Backend repository:

- Backend AWS overlay.
- API, worker, migration, and proof-key seed jobs.
- Managed RDS/Redis runtime wiring.

Default sibling layout:

```text
/Users/chranama/career/inference-serving-gateway
/Users/chranama/career/llm-extraction-platform
```

Override the backend path with `BACKEND_REPO_ROOT` when needed.

## Harness

Canonical harness:

```bash
proof/run_aws_stack.sh
```

Proof artifacts are written to:

```text
proof/artifacts/aws_stack/latest/
```

## Workflow

### 1. Preflight

```bash
proof/run_aws_stack.sh preflight
```

This checks local tooling and repository layout.

### 2. Plan The Substrate

```bash
proof/run_aws_stack.sh terraform-plan
```

Review the plan before applying. The expected substrate is:

- VPC and subnets.
- ECR repositories for both images.
- IAM roles for EKS, worker nodes, and GitHub Actions image publication.
- EKS cluster and bounded managed node group.
- RDS PostgreSQL.
- ElastiCache Redis.

### 3. Apply The Substrate

```bash
proof/run_aws_stack.sh terraform-apply
```

This starts billable AWS resources. Keep the environment short-lived.

### 4. Configure Kubernetes Access

```bash
proof/run_aws_stack.sh kubeconfig
```

### 5. Publish Images

Set both GitHub repository variables:

- `AWS_REGION=us-east-1`
- `AWS_ROLE_TO_ASSUME=<terraform iam_summary.github_actions_role_arn>`

Run the AWS image-publish workflow in both repositories, then deploy with the
published ECR images. If `GATEWAY_IMAGE` and `BACKEND_IMAGE` are unset, the
harness uses each ECR repository's `aws-dev-latest` tag from Terraform output.

### 6. Install AWS Add-Ons

Install CloudWatch Observability:

```bash
proof/run_aws_stack.sh install-cloudwatch
```

This enables the EKS CloudWatch Observability add-on so container logs and
cluster telemetry have a bounded CloudWatch path.

Install the AWS Load Balancer Controller:

```bash
proof/run_aws_stack.sh install-alb-controller
```

The harness follows the AWS Helm/eksctl path:

- create or reuse `AWSLoadBalancerControllerIAMPolicy`;
- create the controller service account with an IAM role;
- install or upgrade the controller with Helm;
- wait for controller rollout.

### 7. Render Manifests

```bash
proof/run_aws_stack.sh render
```

This renders:

- backend overlay from `llm-extraction-platform`;
- gateway overlay from this repository;
- image substitutions from Terraform outputs or explicit image environment
  variables.

Rendered YAML is stored under:

```text
proof/artifacts/aws_stack/latest/rendered/
```

### 8. Deploy Workloads

```bash
proof/run_aws_stack.sh deploy
```

The harness:

- creates or updates namespace `llm`;
- creates `llm-secrets` from Terraform/AWS outputs and proof key environment
  values;
- applies backend manifests;
- applies gateway manifests;
- waits for migrations, proof-key seed, API, worker, gateway, OTel, and Jaeger.

Runtime secret values are not committed.

### 9. Capture Status

```bash
proof/run_aws_stack.sh status
```

This captures pods, services, ingress, events, and ingress description.

### 10. Smoke Through The ALB

```bash
proof/run_aws_stack.sh smoke
```

The proof calls the gateway through the ALB:

- `/healthz`;
- `POST /v1/extract`;
- `POST /v1/extract/jobs`;
- `GET /v1/extract/jobs/{job_id}` until success.

### 11. Inspect

```bash
proof/run_aws_stack.sh inspect
```

This captures:

- gateway logs;
- backend API logs;
- worker logs;
- OTel collector logs;
- gateway metrics;
- backend metrics;
- CloudWatch log group inventory;
- correlated CloudWatch events when the application log group exists.

### 12. Delete Workloads

```bash
proof/run_aws_stack.sh delete-workloads
```

This removes Kubernetes workloads and the runtime secret but keeps the AWS
substrate.

### 13. Destroy The Substrate

```bash
proof/run_aws_stack.sh terraform-destroy
```

This is the expected cleanup path for the first proof slice.

## Acceptance

The proof is acceptable when:

- Terraform provisions the bounded substrate.
- Both images are available in ECR.
- ALB reaches the gateway.
- Gateway reaches the backend API.
- Sync extract succeeds through the ALB.
- Async extract completes through the ALB and worker.
- RDS and Redis are used by the backend.
- Logs and metrics are inspectable.
- CloudWatch log inventory or correlated events are captured.
- The stack can be deleted or destroyed cleanly.
