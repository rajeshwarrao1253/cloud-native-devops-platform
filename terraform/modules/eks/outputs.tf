# ==============================================================================
# EKS Module - Outputs
# ==============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint URL for the EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS control plane"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_primary_security_group_id" {
  description = "Cluster security group created by EKS"
  value       = aws_security_group.cluster.id
}

# ------------------------------------------------------------------------------
# OIDC Outputs
# ------------------------------------------------------------------------------

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = aws_iam_openid_connect_provider.eks.url
}

# ------------------------------------------------------------------------------
# IAM Role Outputs
# ------------------------------------------------------------------------------

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role used by the EKS cluster"
  value       = aws_iam_role.cluster.arn
}

output "cluster_iam_role_name" {
  description = "Name of the IAM role used by the EKS cluster"
  value       = aws_iam_role.cluster.name
}

output "node_group_iam_role_arn" {
  description = "ARN of the IAM role used by EKS node groups"
  value       = aws_iam_role.node_group.arn
}

output "node_group_iam_role_name" {
  description = "Name of the IAM role used by EKS node groups"
  value       = aws_iam_role.node_group.name
}

# ------------------------------------------------------------------------------
# Node Group Outputs
# ------------------------------------------------------------------------------

output "on_demand_node_group_arn" {
  description = "ARN of the on-demand node group"
  value       = length(aws_eks_node_group.on_demand) > 0 ? aws_eks_node_group.on_demand[0].arn : null
}

output "on_demand_node_group_name" {
  description = "Name of the on-demand node group"
  value       = length(aws_eks_node_group.on_demand) > 0 ? aws_eks_node_group.on_demand[0].node_group_name : null
}

output "on_demand_node_group_status" {
  description = "Status of the on-demand node group"
  value       = length(aws_eks_node_group.on_demand) > 0 ? aws_eks_node_group.on_demand[0].status : null
}

output "spot_node_group_arn" {
  description = "ARN of the spot node group"
  value       = length(aws_eks_node_group.spot) > 0 ? aws_eks_node_group.spot[0].arn : null
}

output "spot_node_group_name" {
  description = "Name of the spot node group"
  value       = length(aws_eks_node_group.spot) > 0 ? aws_eks_node_group.spot[0].node_group_name : null
}

output "spot_node_group_status" {
  description = "Status of the spot node group"
  value       = length(aws_eks_node_group.spot) > 0 ? aws_eks_node_group.spot[0].status : null
}

# ------------------------------------------------------------------------------
# IRSA Role Outputs
# ------------------------------------------------------------------------------

output "cluster_autoscaler_iam_role_arn" {
  description = "ARN of the IAM role for Cluster Autoscaler IRSA"
  value       = module.cluster_autoscaler_irsa.iam_role_arn
}

output "ebs_csi_driver_iam_role_arn" {
  description = "ARN of the IAM role for EBS CSI Driver IRSA"
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "aws_load_balancer_controller_iam_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller IRSA"
  value       = module.aws_load_balancer_controller_irsa.iam_role_arn
}

# ------------------------------------------------------------------------------
# Security Group Outputs
# ------------------------------------------------------------------------------

output "node_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.node_group.id
}

# ------------------------------------------------------------------------------
# Fargate Outputs
# ------------------------------------------------------------------------------

output "fargate_profile_arn" {
  description = "ARN of the Fargate profile (if enabled)"
  value       = length(aws_eks_fargate_profile.main) > 0 ? aws_eks_fargate_profile.main[0].arn : null
}

output "fargate_profile_status" {
  description = "Status of the Fargate profile"
  value       = length(aws_eks_fargate_profile.main) > 0 ? aws_eks_fargate_profile.main[0].status : null
}

# ------------------------------------------------------------------------------
# KMS Outputs
# ------------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the KMS key used for secret encryption"
  value       = length(aws_kms_key.eks) > 0 ? aws_kms_key.eks[0].arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key used for secret encryption"
  value       = length(aws_kms_key.eks) > 0 ? aws_kms_key.eks[0].key_id : null
}

# ------------------------------------------------------------------------------
# Addon Outputs
# ------------------------------------------------------------------------------

output "coredns_addon_version" {
  description = "Version of the CoreDNS addon"
  value       = aws_eks_addon.coredns.version
}

output "ebs_csi_driver_addon_version" {
  description = "Version of the EBS CSI driver addon"
  value       = length(aws_eks_addon.ebs_csi) > 0 ? aws_eks_addon.ebs_csi[0].version : null
}
