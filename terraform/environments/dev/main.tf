terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "self-healing-eks"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "iam" {
  source = "../../modules/iam"

  project_name     = var.project_name
  environment      = var.environment
  eks_cluster_name = "${var.project_name}-${var.environment}"

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

module "eks" {
  source = "../../modules/eks"

  project_name    = var.project_name
  environment     = var.environment
  cluster_version = var.cluster_version

  cluster_role_arn = module.iam.eks_cluster_role_arn
  node_role_arn    = module.iam.eks_node_role_arn

  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  on_demand_desired_size = var.on_demand_desired_size
  on_demand_min_size     = var.on_demand_min_size
  on_demand_max_size     = var.on_demand_max_size
  spot_desired_size      = var.spot_desired_size
  spot_min_size          = var.spot_min_size
  spot_max_size          = var.spot_max_size
}

module "rds" {
  source = "../../modules/rds"

  project_name      = var.project_name
  environment       = var.environment
  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  db_instance_class = var.db_instance_class

  private_subnet_ids = module.vpc.private_subnet_ids
  vpc_id             = module.vpc.vpc_id

  eks_node_security_group_id = module.eks.node_security_group_id
}
