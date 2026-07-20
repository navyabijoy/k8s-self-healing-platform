output "vpc_id" {
  description = "The ID of the VPC — other modules need this to place resources inside it"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs — the Load Balancer controller needs these"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs — EKS nodes and RDS go here"
  value       = aws_subnet.private[*].id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC — security groups reference this"
  value       = aws_vpc.main.cidr_block
}
