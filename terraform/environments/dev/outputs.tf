output "cluster_name" {
  description = "Run this to configure kubectl: aws eks update-kubeconfig --name <cluster_name> --region us-east-1"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The Kubernetes API server URL"
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Copy-paste command to configure your local kubectl to talk to this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "db_endpoint" {
  description = "PostgreSQL hostname — put this in your app's DB_HOST environment variable"
  value       = module.rds.db_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN — app reads credentials from here"
  value       = module.rds.db_secret_arn
}

output "vpc_id" {
  description = "VPC ID — useful for adding security group rules manually"
  value       = module.vpc.vpc_id
}
