# ==============================================================================
# Production Environment
# ==============================================================================
# This file composes all Terraform modules for the production environment.
# Production uses maximum redundancy and security:
# - Multi-AZ deployment across all AZs
# - Multi-AZ RDS with read replicas
# - Spot + On-demand mixed node groups
# - Full encryption, private endpoints
# - Extended backup retention
# - MFA delete on S3
# - Container Insights
# - Comprehensive monitoring
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = local.environment
      ManagedBy   = "terraform"
    }
  }
}

# ------------------------------------------------------------------------------
# Local Values
# ------------------------------------------------------------------------------

locals {
  environment = "prod"
  common_tags = {
    Project     = var.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# VPC Module
# ------------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  environment  = local.environment
  vpc_cidr     = "10.2.0.0/16"
  az_count     = 3

  # Full HA - NAT per AZ
  single_nat_gateway = false

  # Full observability
  enable_vpc_flow_logs     = true
  enable_vpc_endpoints     = true
  flow_logs_retention_days = 30

  # Dedicated tenancy for compliance
  dedicated_tenancy = false

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# EKS Module
# ------------------------------------------------------------------------------

module "eks" {
  source = "../../modules/eks"

  project_name = var.project_name
  environment  = local.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr

  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  kubernetes_version = "1.29"

  # Production-grade node groups
  on_demand_instance_types = ["m6i.xlarge"]
  on_demand_desired_size   = 3
  on_demand_min_size       = 3
  on_demand_max_size       = 15

  enable_spot_node_group = true
  spot_instance_types    = ["m6i.xlarge", "m6a.xlarge", "m5.xlarge"]
  spot_desired_size      = 3
  spot_min_size          = 1
  spot_max_size          = 20

  # Full logging
  cluster_log_types          = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_days = 30

  # Security
  enable_private_endpoint = true
  enable_public_endpoint  = true
  public_access_cidrs     = var.allowed_admin_cidrs

  # Full encryption
  enable_secret_encryption = true

  # Security hardening
  bootstrap_cluster_creator_admin_permissions = false

  tags = local.common_tags

  depends_on = [module.vpc]
}

# ------------------------------------------------------------------------------
# RDS Module
# ------------------------------------------------------------------------------

module "rds" {
  source = "../../modules/rds"

  project_name = var.project_name
  environment  = local.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr

  database_subnet_ids = module.vpc.database_subnet_ids

  instance_class        = "db.r5.xlarge"
  allocated_storage     = 100
  max_allocated_storage = 500
  multi_az              = true

  engine_version          = "15.4"
  backup_retention_period = 35
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Read replicas for read scaling
  read_replica_count       = 2
  read_replica_instance_class = "db.r5.large"

  # Production hardening
  deletion_protection = true
  skip_final_snapshot = false

  # Enable IAM database authentication
  iam_database_authentication_enabled = true

  tags = local.common_tags

  depends_on = [module.vpc]
}

# ------------------------------------------------------------------------------
# Redis Module
# ------------------------------------------------------------------------------

module "redis" {
  source = "../../modules/redis"

  project_name = var.project_name
  environment  = local.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr

  database_subnet_ids = module.vpc.database_subnet_ids

  node_type               = "cache.r5.xlarge"
  num_cache_clusters      = 3
  automatic_failover_enabled = true
  multi_az_enabled        = true

  # Full encryption
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"

  snapshot_retention_limit = 7
  snapshot_window          = "05:00-06:00"
  maintenance_window       = "sun:06:00-sun:07:00"

  # Enable CloudWatch logs
  enable_slow_log   = true
  enable_engine_log = true

  tags = local.common_tags

  depends_on = [module.vpc]
}

# ------------------------------------------------------------------------------
# S3 Module
# ------------------------------------------------------------------------------

module "s3" {
  source = "../../modules/s3"

  project_name = var.project_name
  environment  = local.environment

  enable_cloudfront = true
  enable_versioning = true
  enable_mfa_delete = true
  enable_cors       = false

  logs_retention_days = 30

  # CloudFront settings
  cloudfront_price_class = "PriceClass_All"
  min_ttl                = 0
  default_ttl            = 86400
  max_ttl                = 31536000

  # WAF (if ARN provided)
  waf_web_acl_arn = var.waf_web_acl_arn

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# IAM Module
# ------------------------------------------------------------------------------

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = local.environment

  enable_github_actions_oidc = true
  github_org                 = var.github_org

  # Cross-account access (if configured)
  cross_account_trusted_account_id = var.cross_account_trusted_account_id
  cross_account_external_id        = var.cross_account_external_id

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# Monitoring Module
# ------------------------------------------------------------------------------

module "monitoring" {
  source = "../../modules/monitoring"

  project_name     = var.project_name
  environment      = local.environment
  eks_cluster_name = module.eks.cluster_name

  alert_email_addresses = var.alert_email_addresses

  # PagerDuty integration
  pagerduty_integration_endpoint = var.pagerduty_integration_endpoint

  # Full observability
  enable_container_insights = true

  log_retention_days       = 30
  audit_log_retention_days = 365

  # Create all alarms
  create_alarms = true

  tags = local.common_tags

  depends_on = [module.eks]
}

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "cloud-native-devops-platform"
}

variable "github_org" {
  description = "GitHub organization for OIDC"
  type        = string
  default     = "rajeshwarrao1253"
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks allowed to access EKS public endpoint"
  type        = list(string)
  default     = []
}

variable "alert_email_addresses" {
  description = "Email addresses for alerts"
  type        = list(string)
  default     = []
}

variable "pagerduty_integration_endpoint" {
  description = "PagerDuty integration endpoint for alerts"
  type        = string
  default     = null
}

variable "waf_web_acl_arn" {
  description = "ARN of WAF Web ACL for CloudFront"
  type        = string
  default     = null
}

variable "cross_account_trusted_account_id" {
  description = "AWS account ID for cross-account access"
  type        = string
  default     = null
}

variable "cross_account_external_id" {
  description = "External ID for cross-account role"
  type        = string
  default     = null
}
