resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}"
  role_arn = var.cluster_role_arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [var.cluster_role_arn]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_node_group.on_demand]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_node_group.on_demand]
}

resource "aws_eks_node_group" "on_demand" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-on-demand"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.on_demand_instance_types

  scaling_config {
    desired_size = var.on_demand_desired_size
    min_size     = var.on_demand_min_size
    max_size     = var.on_demand_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role        = "system"
    node-type   = "on-demand"
    environment = var.environment
  }

  tags = {
    Name                                                               = "${var.project_name}-${var.environment}-on-demand-node"
    Environment                                                        = var.environment
    "k8s.io/cluster-autoscaler/enabled"                                = "true"
    "k8s.io/cluster-autoscaler/${var.project_name}-${var.environment}" = "owned"
  }
}

resource "aws_eks_node_group" "spot" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-spot"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.spot_instance_types
  capacity_type   = "SPOT"

  scaling_config {
    desired_size = var.spot_desired_size
    min_size     = var.spot_min_size
    max_size     = var.spot_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role        = "app"
    node-type   = "spot"
    environment = var.environment
  }

  taint {
    key    = "node-type"
    value  = "spot"
    effect = "NO_SCHEDULE"
  }

  tags = {
    Name                                                               = "${var.project_name}-${var.environment}-spot-node"
    Environment                                                        = var.environment
    "k8s.io/cluster-autoscaler/enabled"                                = "true"
    "k8s.io/cluster-autoscaler/${var.project_name}-${var.environment}" = "owned"
  }
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name        = "${var.project_name}-${var.environment}-oidc"
    Environment = var.environment
  }
}
