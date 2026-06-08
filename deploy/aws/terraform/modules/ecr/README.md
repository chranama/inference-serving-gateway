# ECR Module

Implements the canonical ECR repositories for the AWS slice:

- `llm-server`
- `inference-serving-gateway`
- force-delete, lifecycle, and scanning defaults for ephemeral proof sessions

First-slice goal:

- keep repository names stable enough within a proof session that contract docs, CI, and deploy notes do not drift apart
- allow full Terraform teardown to delete repositories even when proof images are still present
- keep retention policy intentionally small as a fallback if teardown is delayed
