variable "aws_region" {
  type        = string
  description = "Primary AWS region for the first bounded deployment slice."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Canonical AWS environment name."
  default     = "dev"
}

variable "cluster_name" {
  type        = string
  description = "Canonical EKS cluster name."
  default     = "llm-runtime-dev"
}

variable "namespace" {
  type        = string
  description = "Canonical Kubernetes namespace for the integrated stack."
  default     = "llm"
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to use for the first AWS slice."
  default     = ["us-east-1a"]

  validation {
    condition     = length(var.availability_zones) >= 1
    error_message = "At least one availability zone must be specified."
  }
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Keep false by default for the first bounded AWS slice."
  default     = false
}

variable "ephemeral_environment" {
  type        = bool
  description = "Marks the environment as intended for apply/destroy proof sessions."
  default     = true
}

variable "gateway_ecr_repository_name" {
  type        = string
  description = "Canonical ECR repository name for the gateway image."
  default     = "inference-serving-gateway"
}

variable "backend_ecr_repository_name" {
  type        = string
  description = "Canonical ECR repository name for the backend image."
  default     = "llm-server"
}
