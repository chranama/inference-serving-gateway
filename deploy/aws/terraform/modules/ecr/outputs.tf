output "gateway_repository_name" {
  description = "Gateway ECR repository name."
  value       = aws_ecr_repository.gateway.name
}

output "gateway_repository_arn" {
  description = "Gateway ECR repository ARN."
  value       = aws_ecr_repository.gateway.arn
}

output "gateway_repository_url" {
  description = "Gateway ECR repository URL."
  value       = aws_ecr_repository.gateway.repository_url
}

output "backend_repository_name" {
  description = "Backend ECR repository name."
  value       = aws_ecr_repository.backend.name
}

output "backend_repository_arn" {
  description = "Backend ECR repository ARN."
  value       = aws_ecr_repository.backend.arn
}

output "backend_repository_url" {
  description = "Backend ECR repository URL."
  value       = aws_ecr_repository.backend.repository_url
}
