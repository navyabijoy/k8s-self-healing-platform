variable "project_name" {
  description = "Used as a prefix for the RDS instance identifier"
  type        = string
}

variable "environment" {
  description = "Environment tag"
  type        = string
}

variable "db_name" {
  description = "Name of the initial database to create inside PostgreSQL"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database"
  type        = string
  default     = "appuser"
}

variable "db_password" {
  description = "Master password — in real projects use AWS Secrets Manager or SSM Parameter Store"
  type        = string
  sensitive   = true # Marks this as secret so Terraform won't print it in logs
}

variable "db_instance_class" {
  description = "The EC2 instance size for RDS. 'db.t3.micro' is free-tier eligible."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.4"
}

variable "allocated_storage" {
  description = "Disk size in GB for the database. 20GB is the minimum."
  type        = number
  default     = 20
}

variable "private_subnet_ids" {
  description = "RDS must go in private subnets — no direct internet access. From VPC module."
  type        = list(string)
}

variable "vpc_id" {
  description = "The VPC where RDS security groups will be created"
  type        = string
}

variable "eks_node_security_group_id" {
  description = "The security group of EKS worker nodes — only they are allowed to talk to the DB"
  type        = string
}
