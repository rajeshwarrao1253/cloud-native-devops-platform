# ==============================================================================
# EKS Cluster Module
# ==============================================================================
# This module creates a production-grade EKS cluster with:
# - Managed node groups with mixed on-demand and spot instances
# - Fargate profiles for serverless workloads
# - OIDC provider for IRSA (IAM Roles for Service Accounts)
# - Cluster Autoscaler for automatic node scaling
# - EBS CSI driver for persistent storage
# - AWS Load Balancer Controller
# - IRSA roles for cluster addons
# - Enhanced security with private endpoint access
# ==============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Fetch available AZs
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# EKS optimized AMI for managed node groups
data "aws_ami" "eks_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.kubernetes_version}-v*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------------------
# KMS Key for EKS Secret Encryption
# ------------------------------------------------------------------------------

resource "aws_kms_key" "eks" {
  count = var.enable_secret_encryption ? 1 : 0

  description             = "KMS key for EKS secret encryption (${var.project_name}-${var.environment})"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow EKS Service"
        Effect = "Allow"
        Principal = {
          Service = "eks.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eks-kms"
      Environment = var.environment
    }
  )
}

resource "aws_kms_alias" "eks" {
  count = var.enable_secret_encryption ? 1 : 0

  name          = "alias/${var.project_name}-${var.environment}-eks"
  target_key_id = aws_kms_key.eks[0].key_id
}

# ------------------------------------------------------------------------------
# IAM Role for EKS Cluster
# ------------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eks-cluster-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "cluster_policies" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSVPCResourceController",
  ])

  policy_arn = each.value
  role       = aws_iam_role.cluster.name
}

# ------------------------------------------------------------------------------
# IAM Role for EKS Node Groups
# ------------------------------------------------------------------------------

resource "aws_iam_role" "node_group" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eks-node-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "node_group_policies" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  policy_arn = each.value
  role       = aws_iam_role.node_group.name
}

# S3 access policy for node groups (application logs, etc.)
resource "aws_iam_role_policy" "node_group_s3" {
  count = var.node_group_s3_access ? 1 : 0

  name = "${var.project_name}-${var.environment}-node-s3-policy"
  role = aws_iam_role.node_group.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${var.project_name}-${var.environment}-*",
          "arn:${data.aws_partition.current.partition}:s3:::${var.project_name}-${var.environment}-*/*"
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Security Group for EKS Cluster
# ------------------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name        = "${var.project_name}-${var.environment}-eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  # Allow inbound traffic from worker nodes on port 443
  ingress {
    description     = "Allow worker nodes to communicate with cluster API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.node_group.id]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name                                           = "${var.project_name}-${var.environment}-eks-cluster-sg"
      Environment                                    = var.environment
      "kubernetes.io/cluster/${local.cluster_name}"  = "owned"
    }
  )
}

# ------------------------------------------------------------------------------
# Security Group for Node Groups
# ------------------------------------------------------------------------------

resource "aws_security_group" "node_group" {
  name        = "${var.project_name}-${var.environment}-eks-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  # Allow all traffic between nodes in the same security group
  ingress {
    description = "Allow nodes to communicate with each other"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow inbound traffic from cluster security group
  ingress {
    description     = "Allow cluster control plane to communicate with nodes"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  # Allow SSH if bastion host is enabled
  dynamic "ingress" {
    for_each = var.enable_bastion ? [1] : []
    content {
      description = "Allow SSH from bastion host"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name                                           = "${var.project_name}-${var.environment}-eks-node-sg"
      Environment                                    = var.environment
      "kubernetes.io/cluster/${local.cluster_name}"  = "owned"
    }
  )
}

# ------------------------------------------------------------------------------
# Security Group Rules - Additional
# ------------------------------------------------------------------------------

# Allow pods to communicate with RDS
resource "aws_security_group_rule" "nodes_to_rds" {
  count = var.rds_security_group_id != null ? 1 : 0

  description              = "Allow EKS nodes to communicate with RDS"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.node_group.id
  security_group_id        = var.rds_security_group_id
}

# Allow pods to communicate with Redis
resource "aws_security_group_rule" "nodes_to_redis" {
  count = var.redis_security_group_id != null ? 1 : 0

  description              = "Allow EKS nodes to communicate with Redis"
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.node_group.id
  security_group_id        = var.redis_security_group_id
}

# ------------------------------------------------------------------------------
# EKS Cluster
# ------------------------------------------------------------------------------

locals {
  cluster_name = "${var.project_name}-${var.environment}"
}

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = var.enable_private_endpoint
    endpoint_public_access  = var.enable_public_endpoint
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [aws_security_group.cluster.id]
  }

  # Enable secret encryption with KMS
  dynamic "encryption_config" {
    for_each = var.enable_secret_encryption ? [1] : []
    content {
      provider {
        key_arn = aws_kms_key.eks[0].arn
      }
      resources = ["secrets"]
    }
  }

  # Enable cluster logging
  enabled_cluster_log_types = var.cluster_log_types

  # Upgrade policy
  upgrade_policy {
    support_type = "STANDARD"
  }

  # Access configuration
  access_config {
    authentication_mode                         = var.access_config_authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policies,
    aws_cloudwatch_log_group.eks,
  ]

  tags = merge(
    var.tags,
    {
      Name        = local.cluster_name
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# CloudWatch Log Group for EKS Cluster Logs
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-eks-logs"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# OIDC Provider for IRSA
# ------------------------------------------------------------------------------

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-oidc"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# EKS Managed Node Groups
# ------------------------------------------------------------------------------

# On-demand node group for critical workloads
resource "aws_eks_node_group" "on_demand" {
  count = var.enable_on_demand_node_group ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-on-demand"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_subnet_ids
  ami_type        = var.node_ami_type
  capacity_type   = "ON_DEMAND"
  instance_types  = var.on_demand_instance_types
  disk_size       = var.node_disk_size

  scaling_config {
    desired_size = var.on_demand_desired_size
    min_size     = var.on_demand_min_size
    max_size     = var.on_demand_max_size
  }

  update_config {
    max_unavailable_percentage = var.node_update_max_unavailable_percentage
  }

  labels = merge(
    var.node_labels,
    {
      "node-type"   = "on-demand"
      "environment" = var.environment
    }
  )

  dynamic "taint" {
    for_each = var.on_demand_taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_group_policies,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(
    var.tags,
    {
      Name                                           = "${local.cluster_name}-on-demand"
      Environment                                    = var.environment
      "k8s.io/cluster-autoscaler/enabled"            = "true"
      "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
    }
  )
}

# Spot instance node group for cost-sensitive workloads
resource "aws_eks_node_group" "spot" {
  count = var.enable_spot_node_group ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-spot"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_subnet_ids
  ami_type        = var.node_ami_type
  capacity_type   = "SPOT"
  instance_types  = var.spot_instance_types
  disk_size       = var.node_disk_size

  scaling_config {
    desired_size = var.spot_desired_size
    min_size     = var.spot_min_size
    max_size     = var.spot_max_size
  }

  update_config {
    max_unavailable_percentage = var.node_update_max_unavailable_percentage
  }

  labels = merge(
    var.node_labels,
    {
      "node-type"   = "spot"
      "environment" = var.environment
    }
  )

  taint {
    key    = "spot"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  dynamic "taint" {
    for_each = var.spot_taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_group_policies,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(
    var.tags,
    {
      Name                                           = "${local.cluster_name}-spot"
      Environment                                    = var.environment
      "k8s.io/cluster-autoscaler/enabled"            = "true"
      "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
    }
  )
}

# ------------------------------------------------------------------------------
# Fargate Profile (Optional)
# ------------------------------------------------------------------------------

resource "aws_eks_fargate_profile" "main" {
  count = var.enable_fargate ? 1 : 0

  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "${local.cluster_name}-fargate"
  pod_execution_role_arn = aws_iam_role.fargate[0].arn
  subnet_ids             = var.private_subnet_ids

  dynamic "selector" {
    for_each = var.fargate_selectors
    content {
      namespace = selector.value.namespace
      labels    = lookup(selector.value, "labels", {})
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.fargate_policies,
  ]

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-fargate"
      Environment = var.environment
    }
  )
}

# IAM Role for Fargate
resource "aws_iam_role" "fargate" {
  count = var.enable_fargate ? 1 : 0

  name = "${local.cluster_name}-fargate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-fargate-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "fargate_policies" {
  count = var.enable_fargate ? 1 : 0

  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate[0].name
}

# ------------------------------------------------------------------------------
# Cluster Autoscaler IRSA Role
# ------------------------------------------------------------------------------

module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                        = "${local.cluster_name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [aws_eks_cluster.main.name]

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-cluster-autoscaler"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# EBS CSI Driver IRSA Role
# ------------------------------------------------------------------------------

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${local.cluster_name}-ebs-csi-driver"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-ebs-csi-driver"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# AWS Load Balancer Controller IRSA Role
# ------------------------------------------------------------------------------

module "aws_load_balancer_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${local.cluster_name}-aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-aws-load-balancer-controller"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# EKS Addons
# ------------------------------------------------------------------------------

# CoreDNS
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = var.coredns_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    resources = {
      requests = {
        cpu    = "100m"
        memory = "150Mi"
      }
      limits = {
        memory = "300Mi"
      }
    }
  })

  depends_on = [
    aws_eks_node_group.on_demand,
  ]

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-coredns"
      Environment = var.environment
    }
  )
}

# kube-proxy
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-kube-proxy"
      Environment = var.environment
    }
  )
}

# VPC CNI
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = module.vpc_cni_irsa.iam_role_arn

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
      MINIMUM_IP_TARGET        = "10"
    }
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-vpc-cni"
      Environment = var.environment
    }
  )
}

# EBS CSI Driver
resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_csi_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-ebs-csi"
      Environment = var.environment
    }
  )
}

# VPC CNI IRSA
module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${local.cluster_name}-vpc-cni"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.cluster_name}-vpc-cni"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# AWS Auth ConfigMap (using kubernetes provider)
# ------------------------------------------------------------------------------

# Note: In production, use the aws-auth ConfigMap or EKS Access Entries
# to manage cluster access. The EKS Access Entries API is preferred
# for new clusters (Kubernetes 1.23+).

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------
