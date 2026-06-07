variable "name_prefix" {
  type        = string
  description = "Name prefix for managed data resources."
}

variable "vpc_id" {
  type        = string
  description = "VPC identifier for the managed data resources."
}

variable "vpc_cidr_block" {
  type        = string
  description = "VPC CIDR block allowed to reach the bounded data services."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs used for managed data subnet groups."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Managed data subnet groups require at least two subnet IDs."
  }
}

variable "db_name" {
  type        = string
  description = "Initial Postgres database name."
}

variable "db_username" {
  type        = string
  description = "Master username for the bounded Postgres instance."
}

variable "db_instance_class" {
  type        = string
  description = "Instance class for the bounded Postgres instance."
}

variable "db_allocated_storage" {
  type        = number
  description = "Allocated storage in GiB for Postgres."
}

variable "db_max_allocated_storage" {
  type        = number
  description = "Max autoscaled storage in GiB for Postgres."
}

variable "db_engine_version" {
  type        = string
  description = "Optional explicit Postgres engine version."
  default     = null
}

variable "redis_node_type" {
  type        = string
  description = "Node type for the bounded Redis cluster."
}

variable "redis_engine_version" {
  type        = string
  description = "Optional explicit Redis engine version."
  default     = null
}

variable "ephemeral_environment" {
  type        = bool
  description = "Whether the environment is intended for apply/destroy proof sessions."
}

variable "tags" {
  type        = map(string)
  description = "Base tags applied to managed data resources."
  default     = {}
}
