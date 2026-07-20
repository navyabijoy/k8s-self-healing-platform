variable "project_name" {
  description = "Used as a prefix for all IAM role names"
  type        = string
}

variable "environment" {
  description = "Environment tag (dev/prod)"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster — needed to scope IAM policies"
  type        = string
}

variable "oidc_provider_arn" {
  description = "The ARN of the OIDC provider attached to the EKS cluster. Used for IRSA (IAM Roles for Service Accounts) — lets pods assume IAM roles without storing AWS credentials."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "The URL of the OIDC provider (without https://)"
  type        = string
  default     = ""
}
