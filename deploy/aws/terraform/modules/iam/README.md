# IAM Module

Implements the bounded IAM surface for the AWS slice:

- EKS cluster role
- managed node-group role
- GitHub Actions OIDC provider and ECR publish role

First-slice goal:

- minimum viable IAM surface
- avoid broad or premature IAM sprawl
- make the split between provisioning, publish, and runtime identities explicit before workload deployment begins
