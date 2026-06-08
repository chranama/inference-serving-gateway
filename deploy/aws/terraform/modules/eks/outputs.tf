output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA bundle."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Cluster security group created by EKS."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_group_name" {
  description = "Managed node group name."
  value       = aws_eks_node_group.this.node_group_name
}

output "gpu_node_group_name" {
  description = "Optional model-runtime GPU managed node group name."
  value       = try(aws_eks_node_group.gpu[0].node_group_name, null)
}

output "oidc_issuer" {
  description = "OIDC issuer URL for future workload identity use."
  value       = try(aws_eks_cluster.this.identity[0].oidc[0].issuer, null)
}
