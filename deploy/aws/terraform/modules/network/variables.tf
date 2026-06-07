variable "name_prefix" {
  type        = string
  description = "Name prefix for the bounded network resources."
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name used for subnet tagging."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the bounded VPC."
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones for subnet creation."
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Whether to provision a single NAT gateway for private subnet egress."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Base tags applied to all resources."
  default     = {}
}
