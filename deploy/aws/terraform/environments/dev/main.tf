locals {
  default_tags = {
    project     = "llm-runtime-stack"
    environment = var.environment
    managed_by  = "terraform"
    ephemeral   = tostring(var.ephemeral_environment)
  }

  operator_workflow_contract = {
    smoke = [
      "gateway health through the ALB path",
      "one canonical sync extract request",
      "one canonical async submit-and-complete proof",
    ]
    inspect = [
      "CloudWatch Logs correlated by request_id, trace_id, and job_id",
      "Jaeger trace detail for one sync or async proof run",
      "gateway and backend metrics read against the seeded thresholds",
      "one usage or rough-cost snapshot for the bounded api_key scope",
    ]
    rollback_or_teardown = [
      "manual rollback to the prior image or config revision is acceptable",
      "terraform destroy is acceptable for the bounded dev slice",
    ]
  }

  runtime_contract_seeds = {
    usage_scope_seed = "api_key"
    metering_surfaces = [
      "GET /v1/me/usage",
      "GET /v1/admin/usage",
      "inference logs",
      "proof artifacts",
    ]
    quality_signals = [
      "extract_contract_pass_rate",
      "structured_output_invalid_rate",
      "repair_attempt_rate",
      "repair_success_rate",
      "policy_rejection_rate",
      "async_completion_before_timeout_rate",
      "rough_request_cost_usd",
    ]
    sli_slo_seeds = {
      sync_extract_success_rate            = ">=99% over 1h and 100% on canonical smoke"
      sync_extract_p95_latency_seconds     = "<=2.0s over 5m"
      contract_valid_extract_rate          = ">=98% over 1h"
      async_submit_acceptance_rate         = ">=99% over 1h"
      async_completion_before_timeout_rate = ">=95% over 1h"
    }
    rollback_triggers = [
      "canonical sync smoke fails",
      "canonical async proof fails",
      "sync success or contract-valid rate drops below seed after the current change",
      "sync p95 latency exceeds 2x the recent bounded baseline for 15m",
      "rough request cost jumps materially without an intentional runtime or policy change",
    ]
    first_spend_fairness_control = "one proof-key quota or admission rule with reviewer-visible rejects"
    rough_cost_attribution       = "usage endpoints + inference logs + provider pricing assumptions"
  }

  aws_contract_seed = {
    aws_region                  = var.aws_region
    environment                 = var.environment
    cluster_name                = var.cluster_name
    namespace                   = var.namespace
    availability_zones          = var.availability_zones
    enable_nat_gateway          = var.enable_nat_gateway
    ephemeral_environment       = var.ephemeral_environment
    gateway_ecr_repository_name = var.gateway_ecr_repository_name
    backend_ecr_repository_name = var.backend_ecr_repository_name
    cloud_log_surface           = "CloudWatch Logs"
    trace_surface               = "Jaeger"
    secrets_store               = "Secrets Manager"
    usage_scope_seed            = local.runtime_contract_seeds.usage_scope_seed
  }
}

module "network" {
  source = "../../modules/network"

  name_prefix        = var.cluster_name
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  enable_nat_gateway = var.enable_nat_gateway
  tags               = local.default_tags
}

module "ecr" {
  source = "../../modules/ecr"

  gateway_repository_name = var.gateway_ecr_repository_name
  backend_repository_name = var.backend_ecr_repository_name
  force_delete            = var.ephemeral_environment
  tags                    = local.default_tags
}

module "iam" {
  source = "../../modules/iam"

  name_prefix              = var.cluster_name
  gateway_repository_arn   = module.ecr.gateway_repository_arn
  backend_repository_arn   = module.ecr.backend_repository_arn
  github_oidc_repositories = var.github_oidc_repositories
  github_actions_branch    = var.github_actions_branch
  tags                     = local.default_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name            = var.cluster_name
  cluster_version         = var.cluster_version
  subnet_ids              = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  node_subnet_ids         = module.network.public_subnet_ids
  cluster_role_arn        = module.iam.cluster_role_arn
  node_role_arn           = module.iam.node_role_arn
  node_instance_types     = var.node_instance_types
  node_desired_size       = var.node_desired_size
  node_min_size           = var.node_min_size
  node_max_size           = var.node_max_size
  node_disk_size          = var.node_disk_size
  node_capacity_type      = var.node_capacity_type
  endpoint_public_access  = true
  endpoint_private_access = false
  tags                    = local.default_tags

  depends_on = [module.iam]
}

module "data" {
  source = "../../modules/data"

  name_prefix              = var.cluster_name
  vpc_id                   = module.network.vpc_id
  vpc_cidr_block           = module.network.vpc_cidr_block
  subnet_ids               = module.network.private_subnet_ids
  db_name                  = var.db_name
  db_username              = var.db_username
  db_instance_class        = var.db_instance_class
  db_allocated_storage     = var.db_allocated_storage
  db_max_allocated_storage = var.db_max_allocated_storage
  db_engine_version        = var.db_engine_version
  redis_node_type          = var.redis_node_type
  redis_engine_version     = var.redis_engine_version
  ephemeral_environment    = var.ephemeral_environment
  tags                     = local.default_tags
}

locals {
  resolved_aws_contract = merge(
    local.aws_contract_seed,
    {
      vpc_id                  = module.network.vpc_id
      vpc_cidr                = module.network.vpc_cidr_block
      public_subnet_ids       = module.network.public_subnet_ids
      private_subnet_ids      = module.network.private_subnet_ids
      gateway_repository_url  = module.ecr.gateway_repository_url
      backend_repository_url  = module.ecr.backend_repository_url
      github_actions_role_arn = module.iam.github_actions_role_arn
      eks_cluster_arn         = module.eks.cluster_arn
      eks_cluster_endpoint    = module.eks.cluster_endpoint
      postgres_endpoint       = module.data.postgres_endpoint
      redis_endpoint          = module.data.redis_endpoint
    },
  )
}
