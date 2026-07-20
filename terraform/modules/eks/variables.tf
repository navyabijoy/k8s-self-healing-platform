variable "project_name" {
  description = "Prefix for naming all EKS resources"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use (e.g. '1.29'). Check AWS docs for supported versions."
  type        = string
  default     = "1.29"
}

variable "cluster_role_arn" {
  description = "ARN of the IAM role the EKS control plane will assume. Created in the IAM module."
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the IAM role EKS worker nodes will assume. Created in the IAM module."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs where worker nodes will run. From the VPC module."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs used for the cluster endpoint and load balancers."
  type        = list(string)
}

variable "on_demand_instance_types" {
  description = "EC2 instance types for the on-demand node group (stable, always-on nodes for system workloads)"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "spot_instance_types" {
  description = "EC2 instance types for the spot node group (cheaper but can be interrupted — used for app workloads)"
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

variable "on_demand_desired_size" {
  description = "How many on-demand nodes to run normally"
  type        = number
  default     = 2
}

variable "on_demand_min_size" {
  description = "Minimum on-demand nodes (cluster autoscaler won't go below this)"
  type        = number
  default     = 1
}

variable "on_demand_max_size" {
  description = "Maximum on-demand nodes (cluster autoscaler won't go above this)"
  type        = number
  default     = 3
}

variable "spot_desired_size" {
  description = "How many spot nodes to run normally"
  type        = number
  default     = 1
}

variable "spot_min_size" {
  description = "Minimum spot nodes"
  type        = number
  default     = 0
}

variable "spot_max_size" {
  description = "Maximum spot nodes"
  type        = number
  default     = 5
}
