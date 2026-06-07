output "cluster_role_arn" {
  description = "IAM role ARN for the EKS control plane."
  value       = aws_iam_role.eks_cluster.arn
}

output "node_role_arn" {
  description = "IAM role ARN for the managed node group."
  value       = aws_iam_role.eks_node.arn
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions image publication, if enabled."
  value       = local.github_actions_enabled ? aws_iam_role.github_actions_image_publish[0].arn : null
}
