output "aws_contract" {
  description = "Current bounded AWS deployment contract for the dev environment."
  value       = local.aws_contract
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
