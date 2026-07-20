variable "aws_region" {
  description = "AWS region to deploy everything into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as prefix for all resources"
  type        = string
  default     = "self-healing-eks"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

# VPC
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# EKS Node Groups
variable "on_demand_desired_size" {
  type    = number
  default = 2
}

variable "on_demand_min_size" {
  type    = number
  default = 1
}

variable "on_demand_max_size" {
  type    = number
  default = 3
}

variable "spot_desired_size" {
  type    = number
  default = 1
}

variable "spot_min_size" {
  type    = number
  default = 0
}

variable "spot_max_size" {
  type    = number
  default = 5
}

# RDS
variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
  # Set via: export TF_VAR_db_password="yourpassword"
  # Or in a terraform.tfvars file (add that file to .gitignore!)
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro" # Free tier eligible!
}
