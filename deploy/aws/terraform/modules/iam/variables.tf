variable "name_prefix" {
  type        = string
  description = "Name prefix for IAM roles and policies."
}

variable "gateway_repository_arn" {
  type        = string
  description = "Gateway ECR repository ARN for push permissions."
}

variable "backend_repository_arn" {
  type        = string
  description = "Backend ECR repository ARN for push permissions."
}

variable "github_oidc_repositories" {
  type        = list(string)
  description = "GitHub repositories allowed to assume the publish role."
  default     = []
}

variable "github_actions_branch" {
  type        = string
  description = "Git branch permitted to assume the GitHub Actions publish role."
  default     = "main"
}

variable "github_oidc_thumbprints" {
  type        = list(string)
  description = "Thumbprints for the GitHub Actions OIDC provider."
  default     = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

variable "tags" {
  type        = map(string)
  description = "Base tags applied to IAM resources."
  default     = {}
}
