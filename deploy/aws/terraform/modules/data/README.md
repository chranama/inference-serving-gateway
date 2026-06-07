# Data Module

Implements the bounded managed data substrate:

- `RDS PostgreSQL`
- `ElastiCache Redis`
- subnet groups for both services
- security groups scoped to the bounded VPC CIDR

First-slice goal:

- dev-only managed data services
- no premature failover or HA posture claims
- enough managed state to keep later app rollout off in-cluster Postgres/Redis
