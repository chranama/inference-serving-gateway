# AWS Runbook

This runbook executes the bounded AWS deployment slice for the integrated
`inference-serving-gateway` plus `llm-extraction-platform` stack.

The goal is a short-lived proof deployment:

```text
ALB
  -> inference-serving-gateway
      -> llm-extraction-platform API
      -> llm-extraction-platform worker
      -> optional vLLM model runtime
      -> RDS PostgreSQL
      -> ElastiCache Redis
```

The AWS proof has two promoted workflows:

| Workflow | Purpose | Backend Runtime | Artifact Directory |
|---|---|---|---|
| `AWS_WORKFLOW=fake` | Prove cloud deployment, service boundaries, managed data, request identity, and inspection with a deterministic backend | In-process fake backend in the backend API image | `proof/artifacts/aws_stack/latest/` |
| `AWS_WORKFLOW=vllm` | Prove the same stack with a live OpenAI-compatible model runtime | Separate `vllm/vllm-openai` Deployment on a GPU node group | `proof/artifacts/aws_stack/vllm_latest/` |

Both workflows keep the gateway as the public ingress boundary. The vLLM path
adds a model-runtime service, but it does not make the model backend public.

The proof does not promote custom domains, WAF, production HA, or always-on
operation.

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
- Optional vLLM model-runtime overlay for the live backend workflow.

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

Select the workflow with `AWS_WORKFLOW`:

```bash
AWS_WORKFLOW=fake proof/run_aws_stack.sh <command>
AWS_WORKFLOW=vllm proof/run_aws_stack.sh <command>
```

If `AWS_WORKFLOW` is unset, the harness defaults to `fake`.

## Workflow

### 1. Preflight

```bash
proof/run_aws_stack.sh preflight
```

This checks local tooling and repository layout.

For the live model workflow, preflight also checks AWS identity and the regional
EC2 GPU-family vCPU quota before Terraform creates the GPU node group:

```bash
AWS_WORKFLOW=vllm proof/run_aws_stack.sh preflight
```

The promoted vLLM node target is `g6.xlarge`, which requires 4 vCPUs from the
`Running On-Demand G and VT instances` EC2 quota in `us-east-1`. The harness
stores the quota response in:

```text
proof/artifacts/aws_stack/vllm_latest/preflight/ec2_gpu_vcpu_quota.json
```

If the quota is lower than the required value, request an increase in Service
Quotas before running `terraform-apply`. Override the check only when the
Terraform GPU target changes:

```bash
AWS_WORKFLOW=vllm AWS_GPU_REQUIRED_VCPUS=8 proof/run_aws_stack.sh preflight
```

### 2. Plan The Substrate

For the deterministic workflow, the default `terraform.tfvars` shape is enough.
For the vLLM workflow, enable the GPU node group before planning:

```hcl
enable_gpu_node_group = true
gpu_node_instance_types = ["g6.xlarge"]
gpu_node_desired_size = 1
gpu_node_min_size = 0
gpu_node_max_size = 1
```

```bash
proof/run_aws_stack.sh terraform-plan
```

Review the plan before applying. The expected substrate is:

- VPC and subnets.
- Ephemeral ECR repositories for both application images.
- IAM roles for EKS, worker nodes, and GitHub Actions image publication.
- EKS cluster and bounded managed node group.
- Optional GPU managed node group for `AWS_WORKFLOW=vllm`.
- RDS PostgreSQL.
- ElastiCache Redis.

### 3. Apply The Substrate

```bash
proof/run_aws_stack.sh terraform-apply
```

This starts billable AWS resources. Keep the environment short-lived.
The ECR repositories are created as part of this substrate and are expected to
exist only for the proof session.

### 4. Configure Kubernetes Access

```bash
proof/run_aws_stack.sh kubeconfig
```

### 5. Publish Images

Set both GitHub repository variables:

- `AWS_REGION=us-east-1`
- `AWS_ROLE_TO_ASSUME=<terraform iam_summary.github_actions_role_arn>`

Run the manual AWS image-publish workflow in both repositories after
`terraform-apply`. The workflows refuse to publish unless the target ECR
repository exists and is tagged as a Terraform-owned ephemeral repository.

If `GATEWAY_IMAGE` and `BACKEND_IMAGE` are unset, the harness uses each
ephemeral ECR repository's `aws-dev-latest` tag from Terraform output. For a
more exact proof, set those variables to the `git-<sha>` or `run-<id>` tags
reported by the workflow artifacts.

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

For `AWS_WORKFLOW=vllm`, install the NVIDIA device plugin after the GPU node
group exists:

```bash
AWS_WORKFLOW=vllm proof/run_aws_stack.sh install-gpu-device-plugin
```

The vLLM pod requests `nvidia.com/gpu: 1` and is scheduled only on nodes labeled
for the model-runtime workload.

### 7. Render Manifests

```bash
proof/run_aws_stack.sh render
```

This renders:

- backend overlay from `llm-extraction-platform`;
- gateway overlay from this repository;
- vLLM Deployment and Service when `AWS_WORKFLOW=vllm`;
- image substitutions from Terraform outputs or explicit image environment
  variables.

Rendered YAML is stored under:

```text
proof/artifacts/aws_stack/latest/rendered/
proof/artifacts/aws_stack/vllm_latest/rendered/
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
- waits for migrations, proof-key seed, API, worker, gateway, OTel, and Jaeger;
- waits for vLLM rollout when `AWS_WORKFLOW=vllm`.

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
- vLLM logs and metrics when `AWS_WORKFLOW=vllm`;
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
substrate, including ECR repositories and pushed images. Use this only for
inspection or before a same-session redeploy.

### 13. Destroy The Substrate

```bash
proof/run_aws_stack.sh terraform-destroy
```

This is the expected cleanup path for the first proof slice. It deletes the
Terraform-owned ECR repositories and the images pushed for the proof session.

## Acceptance

The proof is acceptable when:

- Terraform provisions the bounded substrate.
- Both images are available in the ephemeral ECR repositories.
- ALB reaches the gateway.
- Gateway reaches the backend API.
- Sync extract succeeds through the ALB.
- Async extract completes through the ALB and worker.
- RDS and Redis are used by the backend.
- Logs and metrics are inspectable.
- CloudWatch log inventory or correlated events are captured.
- Workloads can be deleted for inspection, and the full substrate can be
  destroyed cleanly at the end of the proof session.

For `AWS_WORKFLOW=vllm`, the proof is acceptable only when the GPU node group is
present, the NVIDIA device plugin is installed, vLLM becomes ready, and extract
traffic succeeds through the same ALB -> gateway -> backend path.
