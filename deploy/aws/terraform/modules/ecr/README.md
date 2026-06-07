# ECR Module

Implements the canonical ECR repositories for the AWS slice:

- `llm-server`
- `inference-serving-gateway`
- basic lifecycle and scanning defaults

First-slice goal:

- keep repository names stable enough that contract docs, CI, and deploy notes do not drift apart
- keep retention policy intentionally small for a bounded proof environment
