output "aws_contract" {
  description = "Current bounded AWS deployment contract for the dev environment."
  value       = local.resolved_aws_contract
}

output "cost_guardrails" {
  description = "Current first-slice cost controls encoded into the Terraform scaffold."
  value = {
    single_region            = true
    environment              = var.environment
    availability_zones       = var.availability_zones
    enable_nat_gateway       = var.enable_nat_gateway
    ephemeral_environment    = var.ephemeral_environment
    custom_domain_required   = false
    intended_cluster_shape   = "one bounded node group"
    intended_runtime_posture = "proof_or_test_sessions"
  }
}

output "runtime_contract_seeds" {
  description = "Seeded runtime, usage, and rollback expectations that later AWS slices should preserve."
  value       = local.runtime_contract_seeds
}

output "operator_workflow_contract" {
  description = "The bounded smoke, inspection, and rollback-or-teardown workflow shape for the first AWS slice."
  value       = local.operator_workflow_contract
}

output "network_summary" {
  description = "Bounded VPC and subnet outputs for the AWS substrate."
  value = {
    vpc_id             = module.network.vpc_id
    vpc_cidr_block     = module.network.vpc_cidr_block
    public_subnet_ids  = module.network.public_subnet_ids
    private_subnet_ids = module.network.private_subnet_ids
  }
}

output "ecr_summary" {
  description = "Canonical ECR repositories for the gateway and backend images."
  value = {
    gateway_name = module.ecr.gateway_repository_name
    gateway_url  = module.ecr.gateway_repository_url
    backend_name = module.ecr.backend_repository_name
    backend_url  = module.ecr.backend_repository_url
  }
}

output "iam_summary" {
  description = "IAM roles created for cluster, nodes, and GitHub-based image publication."
  value = {
    cluster_role_arn        = module.iam.cluster_role_arn
    node_role_arn           = module.iam.node_role_arn
    github_actions_role_arn = module.iam.github_actions_role_arn
  }
}

output "cluster_summary" {
  description = "Bounded EKS outputs for later add-on and workload deployment slices."
  value = {
    cluster_name              = module.eks.cluster_name
    cluster_arn               = module.eks.cluster_arn
    cluster_endpoint          = module.eks.cluster_endpoint
    cluster_security_group_id = module.eks.cluster_security_group_id
    node_group_name           = module.eks.node_group_name
    oidc_issuer               = module.eks.oidc_issuer
  }
}

output "managed_data_summary" {
  description = "Managed Postgres and Redis endpoints for the bounded AWS slice."
  value = {
    postgres_endpoint          = module.data.postgres_endpoint
    postgres_port              = module.data.postgres_port
    postgres_db_name           = module.data.postgres_db_name
    postgres_master_secret_arn = module.data.postgres_master_secret_arn
    redis_endpoint             = module.data.redis_endpoint
    redis_port                 = module.data.redis_port
  }
}
