# ==============================================================================
# EKS Module - Variables
# ==============================================================================

# ------------------------------------------------------------------------------
# Required Variables
# ------------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS worker nodes"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for load balancers"
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------
# Cluster Configuration
# ------------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "cluster_log_types" {
  description = "List of enabled cluster log types"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "CloudWatch log retention for cluster logs"
  type        = number
  default     = 30
}

variable "enable_private_endpoint" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "enable_public_endpoint" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_secret_encryption" {
  description = "Enable KMS encryption for Kubernetes secrets"
  type        = bool
  default     = true
}

variable "access_config_authentication_mode" {
  description = "Authentication mode for EKS access entries"
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Give cluster creator admin permissions"
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# Node Group Configuration - On-Demand
# ------------------------------------------------------------------------------

variable "enable_on_demand_node_group" {
  description = "Enable on-demand managed node group"
  type        = bool
  default     = true
}

variable "on_demand_instance_types" {
  description = "Instance types for on-demand node group"
  type        = list(string)
  default     = ["m6i.large", "m6i.xlarge"]
}

variable "on_demand_desired_size" {
  description = "Desired number of on-demand nodes"
  type        = number
  default     = 2
}

variable "on_demand_min_size" {
  description = "Minimum number of on-demand nodes"
  type        = number
  default     = 1
}

variable "on_demand_max_size" {
  description = "Maximum number of on-demand nodes"
  type        = number
  default     = 10
}

variable "on_demand_taints" {
  description = "Taints for on-demand node group"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

# ------------------------------------------------------------------------------
# Node Group Configuration - Spot
# ------------------------------------------------------------------------------

variable "enable_spot_node_group" {
  description = "Enable spot instance node group"
  type        = bool
  default     = true
}

variable "spot_instance_types" {
  description = "Instance types for spot node group (multiple for diversification)"
  type        = list(string)
  default     = ["m6i.large", "m5.large", "m5a.large"]
}

variable "spot_desired_size" {
  description = "Desired number of spot nodes"
  type        = number
  default     = 1
}

variable "spot_min_size" {
  description = "Minimum number of spot nodes"
  type        = number
  default     = 0
}

variable "spot_max_size" {
  description = "Maximum number of spot nodes"
  type        = number
  default     = 15
}

variable "spot_taints" {
  description = "Additional taints for spot node group"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

# ------------------------------------------------------------------------------
# General Node Configuration
# ------------------------------------------------------------------------------

variable "node_ami_type" {
  description = "AMI type for node groups (AL2_x86_64, AL2_x86_64_GPU, AL2_ARM_64, BOTTLEROCKET_x86_64)"
  type        = string
  default     = "AL2_x86_64"
}

variable "node_disk_size" {
  description = "Disk size (GB) for worker nodes"
  type        = number
  default     = 50
}

variable "node_labels" {
  description = "Common labels for all node groups"
  type        = map(string)
  default     = {}
}

variable "node_update_max_unavailable_percentage" {
  description = "Max percentage of unavailable nodes during update"
  type        = number
  default     = 25
}

variable "node_group_s3_access" {
  description = "Enable S3 access for node groups"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Fargate Configuration
# ------------------------------------------------------------------------------

variable "enable_fargate" {
  description = "Enable Fargate profiles"
  type        = bool
  default     = false
}

variable "fargate_selectors" {
  description = "Namespace and label selectors for Fargate profiles"
  type = list(object({
    namespace = string
    labels    = optional(map(string), {})
  }))
  default = []
}

# ------------------------------------------------------------------------------
# Addons
# ------------------------------------------------------------------------------

variable "enable_ebs_csi_driver" {
  description = "Enable EBS CSI driver addon"
  type        = bool
  default     = true
}

variable "coredns_version" {
  description = "CoreDNS addon version (null for latest)"
  type        = string
  default     = null
}

variable "kube_proxy_version" {
  description = "kube-proxy addon version (null for latest)"
  type        = string
  default     = null
}

variable "vpc_cni_version" {
  description = "VPC CNI addon version (null for latest)"
  type        = string
  default     = null
}

variable "ebs_csi_version" {
  description = "EBS CSI driver addon version (null for latest)"
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# Security
# ------------------------------------------------------------------------------

variable "enable_bastion" {
  description = "Enable bastion host access for nodes"
  type        = bool
  default     = false
}

variable "rds_security_group_id" {
  description = "Security group ID of RDS for node access rules"
  type        = string
  default     = null
}

variable "redis_security_group_id" {
  description = "Security group ID of ElastiCache for node access rules"
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption"
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
