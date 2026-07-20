output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role — passed to the EKS module"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role — passed to the EKS node group"
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_role_name" {
  description = "Name of the EKS node IAM role"
  value       = aws_iam_role.eks_node.name
}

output "cloudwatch_agent_role_arn" {
  description = "ARN of the CloudWatch agent IRSA role — annotated on the K8s service account"
  value       = var.oidc_provider_arn != "" ? aws_iam_role.cloudwatch_agent[0].arn : ""
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IRSA role"
  value       = var.oidc_provider_arn != "" ? aws_iam_role.cluster_autoscaler[0].arn : ""
}
