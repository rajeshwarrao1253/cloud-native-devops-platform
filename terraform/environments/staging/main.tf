# ==============================================================================
# Staging Environment
# ==============================================================================
# This file composes all Terraform modules for the staging environment.
# Staging mirrors production configuration but with smaller instance sizes.
# Used for integration testing and pre-production validation.
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
  environment = "staging"
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
  vpc_cidr     = "10.1.0.0/16"
  az_count     = 3

  single_nat_gateway = false  # Production-like HA

  enable_vpc_flow_logs     = true
  enable_vpc_endpoints     = true
  flow_logs_retention_days = 14

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

  # Staging-sized node groups
  on_demand_instance_types = ["m6i.large"]
  on_demand_desired_size   = 2
  on_demand_min_size       = 2
  on_demand_max_size       = 6

  enable_spot_node_group = true
  spot_instance_types    = ["m6i.large", "m5.large", "m5a.large"]
  spot_desired_size      = 2
  spot_min_size          = 1
  spot_max_size          = 8

  cluster_log_retention_days = 14

  enable_private_endpoint = true
  enable_public_endpoint  = true

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

  instance_class        = "db.r5.large"
  allocated_storage     = 50
  max_allocated_storage = 100
  multi_az              = true

  engine_version          = "15.4"
  backup_retention_period = 7

  performance_insights_enabled = true
  performance_insights_retention_period = 7

  read_replica_count = 1

  skip_final_snapshot = false

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

  node_type               = "cache.r5.large"
  num_cache_clusters      = 3
  automatic_failover_enabled = true
  multi_az_enabled        = true

  snapshot_retention_limit = 7

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
  enable_cors       = false

  logs_retention_days = 14

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

  log_retention_days       = 14
  audit_log_retention_days = 90

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

variable "alert_email_addresses" {
  description = "Email addresses for alerts"
  type        = list(string)
  default     = []
}
