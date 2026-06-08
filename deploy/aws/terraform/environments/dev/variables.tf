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
  description = "Availability zones to use for the first AWS slice. Managed data subnet groups require at least two."
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required for the bounded managed-data substrate."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "Primary VPC CIDR block for the bounded AWS substrate."
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
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

variable "cluster_version" {
  type        = string
  description = "Optional explicit EKS Kubernetes version. Use null to accept the AWS default supported version."
  default     = null
}

variable "node_instance_types" {
  type        = list(string)
  description = "Managed node group instance types for the first bounded cluster."
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type        = number
  description = "Desired node count for the bounded node group."
  default     = 2
}

variable "node_min_size" {
  type        = number
  description = "Minimum node count for the bounded node group."
  default     = 1
}

variable "node_max_size" {
  type        = number
  description = "Maximum node count for the bounded node group."
  default     = 3
}

variable "node_disk_size" {
  type        = number
  description = "Disk size in GiB for managed node group instances."
  default     = 20
}

variable "node_capacity_type" {
  type        = string
  description = "Capacity type for the first bounded node group."
  default     = "ON_DEMAND"
}

variable "enable_gpu_node_group" {
  type        = bool
  description = "Whether to create the optional model-runtime GPU node group for the vLLM AWS workflow."
  default     = false
}

variable "gpu_node_instance_types" {
  type        = list(string)
  description = "Instance types for the optional model-runtime GPU node group."
  default     = ["g6.xlarge"]
}

variable "gpu_node_desired_size" {
  type        = number
  description = "Desired node count for the optional model-runtime GPU node group."
  default     = 1
}

variable "gpu_node_min_size" {
  type        = number
  description = "Minimum node count for the optional model-runtime GPU node group."
  default     = 0
}

variable "gpu_node_max_size" {
  type        = number
  description = "Maximum node count for the optional model-runtime GPU node group."
  default     = 1
}

variable "gpu_node_disk_size" {
  type        = number
  description = "Disk size in GiB for each optional model-runtime GPU node."
  default     = 120
}

variable "gpu_node_capacity_type" {
  type        = string
  description = "Capacity type for the optional model-runtime GPU node group."
  default     = "ON_DEMAND"
}

variable "db_name" {
  type        = string
  description = "Initial Postgres database name for the platform."
  default     = "llm"
}

variable "db_username" {
  type        = string
  description = "Master username for the bounded Postgres instance."
  default     = "llm"
}

variable "db_instance_class" {
  type        = string
  description = "Instance class for the bounded Postgres instance."
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  type        = number
  description = "Allocated storage in GiB for the bounded Postgres instance."
  default     = 20
}

variable "db_max_allocated_storage" {
  type        = number
  description = "Max autoscaled storage in GiB for the bounded Postgres instance."
  default     = 100
}

variable "db_engine_version" {
  type        = string
  description = "Optional explicit Postgres engine version. Use null to accept the provider default."
  default     = null
}

variable "redis_node_type" {
  type        = string
  description = "Node type for the bounded Redis cache."
  default     = "cache.t3.micro"
}

variable "redis_engine_version" {
  type        = string
  description = "Optional explicit Redis engine version. Use null to accept the provider default."
  default     = null
}

variable "github_oidc_repositories" {
  type        = list(string)
  description = "GitHub repositories allowed to assume the bounded ECR publish role."
  default = [
    "chranama/inference-serving-gateway",
    "chranama/llm-extraction-platform",
  ]
}

variable "github_actions_branch" {
  type        = string
  description = "Git branch allowed to assume the bounded GitHub Actions publish role."
  default     = "main"
}
