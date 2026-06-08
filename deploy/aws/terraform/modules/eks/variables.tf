variable "cluster_name" {
  type        = string
  description = "Name of the bounded EKS cluster."
}

variable "cluster_version" {
  type        = string
  description = "Optional Kubernetes version for the EKS cluster."
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs used by the EKS control plane."
}

variable "node_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs used by the managed node group."
}

variable "cluster_role_arn" {
  type        = string
  description = "IAM role ARN for the EKS control plane."
}

variable "node_role_arn" {
  type        = string
  description = "IAM role ARN for the managed node group."
}

variable "node_group_name" {
  type        = string
  description = "Suffix used for the default node group."
  default     = "system"
}

variable "node_instance_types" {
  type        = list(string)
  description = "Instance types for the bounded node group."
}

variable "node_desired_size" {
  type        = number
  description = "Desired node count for the bounded node group."
}

variable "node_min_size" {
  type        = number
  description = "Minimum node count for the bounded node group."
}

variable "node_max_size" {
  type        = number
  description = "Maximum node count for the bounded node group."
}

variable "node_disk_size" {
  type        = number
  description = "Disk size in GiB for each managed node."
}

variable "node_capacity_type" {
  type        = string
  description = "Capacity type for the bounded node group."
  default     = "ON_DEMAND"
}

variable "enable_gpu_node_group" {
  type        = bool
  description = "Whether to create the optional model-runtime GPU node group."
  default     = false
}

variable "gpu_node_group_name" {
  type        = string
  description = "Suffix used for the optional model-runtime GPU node group."
  default     = "model"
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

variable "gpu_node_ami_type" {
  type        = string
  description = "EKS optimized accelerated AMI type for the optional GPU node group."
  default     = "AL2023_x86_64_NVIDIA"
}

variable "endpoint_public_access" {
  type        = bool
  description = "Whether the EKS API endpoint is public."
  default     = true
}

variable "endpoint_private_access" {
  type        = bool
  description = "Whether the EKS API endpoint is private."
  default     = false
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "Optional EKS control-plane log types."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Base tags applied to EKS resources."
  default     = {}
}
