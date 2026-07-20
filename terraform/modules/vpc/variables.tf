variable "project_name" {
  description = "A name prefix used to tag and name every resource (e.g. 'self-healing-eks')"
  type        = string
}

variable "environment" {
  description = "The environment this infra belongs to (e.g. 'dev', 'prod')"
  type        = string
}

variable "vpc_cidr" {
  description = "The IP address range for the whole VPC (e.g. '10.0.0.0/16' gives you 65 536 addresses)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per Availability Zone). Public subnets hold the load balancer."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (one per AZ). EKS worker nodes and RDS live here."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "availability_zones" {
  description = "Which AWS Availability Zones to spread resources across for high availability"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
