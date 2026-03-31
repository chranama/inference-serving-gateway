locals {
  default_tags = {
    project     = "llm-runtime-stack"
    environment = var.environment
    managed_by  = "terraform"
    ephemeral   = tostring(var.ephemeral_environment)
  }

  aws_contract = {
    aws_region                  = var.aws_region
    environment                 = var.environment
    cluster_name                = var.cluster_name
    namespace                   = var.namespace
    availability_zones          = var.availability_zones
    enable_nat_gateway          = var.enable_nat_gateway
    ephemeral_environment       = var.ephemeral_environment
    gateway_ecr_repository_name = var.gateway_ecr_repository_name
    backend_ecr_repository_name = var.backend_ecr_repository_name
  }
}

# Phase 2.3.1 intentionally stops at contract + scaffold.
# Module wiring begins in later 2.3.x slices once the AWS contract is fixed.
