# ==============================================================================
# Development Environment
# ==============================================================================
# This file composes all Terraform modules for the development environment.
# Dev environment uses cost-optimized configurations:
# - Single NAT Gateway (not one per AZ)
# - Smaller instance types
# - Shorter backup retention
# - Spot instances enabled for worker nodes
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
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ------------------------------------------------------------------------------
# Local Values
# ------------------------------------------------------------------------------

locals {
  environment = "dev"
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
  vpc_cidr     = "10.0.0.0/16"
  az_count     = 2

  # Cost optimizations for dev
  single_nat_gateway = true

  # Features
  enable_vpc_flow_logs     = true
  enable_vpc_endpoints     = true
  flow_logs_retention_days = 7

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

  # Dev-sized node groups
  on_demand_instance_types = ["t3.medium"]
  on_demand_desired_size   = 1
  on_demand_min_size       = 1
  on_demand_max_size       = 3

  # Enable spot for cost savings
  enable_spot_node_group = true
  spot_instance_types    = ["t3.medium", "t3a.medium"]
  spot_desired_size      = 1
  spot_min_size          = 0
  spot_max_size          = 5

  cluster_log_retention_days = 7

  # Security
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

  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  max_allocated_storage = 50
  multi_az              = false  # Cost optimization for dev

  engine_version          = "15.4"
  backup_retention_period = 3

  # Performance insights not needed for dev
  performance_insights_enabled = false

  # Dev can skip final snapshot
  skip_final_snapshot = true

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

  node_type               = "cache.t3.micro"
  num_cache_clusters      = 2
  automatic_failover_enabled = true

  snapshot_retention_limit = 3

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

  # CORS for local development
  enable_cors             = true
  cors_allowed_origins    = ["http://localhost:3000", "https://dev.${var.project_name}.com"]
  cors_allowed_methods    = ["GET", "HEAD", "POST", "PUT"]

  logs_retention_days = 7

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

  log_retention_days       = 7
  audit_log_retention_days = 30

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
