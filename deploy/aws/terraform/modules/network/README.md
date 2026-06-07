# Network Module

Implements the bounded network substrate for the first AWS slice:

- VPC
- public subnets for the initial node-group and ingress posture
- private subnets for managed data services
- internet gateway
- shared public/private route tables
- optional single `NAT Gateway`

Important first-slice rule:

- `NAT Gateway` is disabled by default unless a later implementation step proves it is required

Current posture:

- public subnets are tagged for later `ALB` discovery
- private subnets are reserved for managed data and later internal load-balancer use
