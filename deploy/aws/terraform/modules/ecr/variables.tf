variable "gateway_repository_name" {
  type        = string
  description = "ECR repository name for the gateway image."
}

variable "backend_repository_name" {
  type        = string
  description = "ECR repository name for the backend image."
}

variable "force_delete" {
  type        = bool
  description = "Whether repositories may be deleted even when they still contain proof-session images."
  default     = true
}

variable "image_retention_count" {
  type        = number
  description = "How many tagged images to retain if a proof-session repository is not immediately destroyed."
  default     = 5
}

variable "tags" {
  type        = map(string)
  description = "Base tags applied to the ECR repositories."
  default     = {}
}
