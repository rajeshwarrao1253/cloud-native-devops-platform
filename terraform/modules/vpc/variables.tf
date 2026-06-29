# ==============================================================================
# VPC Module - Variables
# ==============================================================================

# ------------------------------------------------------------------------------
# Required Variables
# ------------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project, used as a prefix for all resources"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g., 10.0.0.0/16)"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

# ------------------------------------------------------------------------------
# Optional Variables
# ------------------------------------------------------------------------------

variable "az_count" {
  description = "Number of availability zones to use (1-3)"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "AZ count must be between 1 and 3."
  }
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all AZs (cost-saving for dev)"
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "CloudWatch Logs retention period for VPC Flow Logs"
  type        = number
  default     = 30
}

variable "flow_log_format" {
  description = "Custom format for VPC Flow Logs"
  type        = string
  default     = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr}"
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services (reduces NAT costs)"
  type        = bool
  default     = true
}

variable "dedicated_tenancy" {
  description = "Enable dedicated instance tenancy for compliance"
  type        = bool
  default     = false
}

variable "enable_ipv6" {
  description = "Enable IPv6 support in the VPC"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encrypting CloudWatch Logs"
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# VPC Peering Variables (Optional)
# ------------------------------------------------------------------------------

variable "vpc_peering_enabled" {
  description = "Enable VPC peering"
  type        = bool
  default     = false
}

variable "peer_vpc_id" {
  description = "ID of the peer VPC for VPC peering"
  type        = string
  default     = null
}

variable "peer_owner_id" {
  description = "AWS Account ID of the peer VPC owner"
  type        = string
  default     = null
}

variable "peer_region" {
  description = "Region of the peer VPC (if cross-region peering)"
  type        = string
  default     = null
}

variable "peer_vpc_cidr" {
  description = "CIDR block of the peer VPC"
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
