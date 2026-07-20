output "cluster_id" {
  description = "The name/ID of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_endpoint" {
  description = "The URL to the Kubernetes API server — used by kubectl and Helm"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate for authenticating with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_name" {
  description = "The name of the EKS cluster (used in aws eks update-kubeconfig)"
  value       = aws_eks_cluster.main.name
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — passed to IAM module to create IRSA roles"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider (without https://)"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

output "node_security_group_id" {
  description = "Security group ID attached to all EKS worker nodes — used by RDS to allow access"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
