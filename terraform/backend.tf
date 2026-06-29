# ==============================================================================
# Terraform Backend Configuration
# ==============================================================================
# This file configures the remote backend for Terraform state management.
# State is stored in S3 with DynamoDB table for state locking.
# This ensures safe collaboration and prevents concurrent modifications.
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Backend configuration - must be initialized per environment
  # Use: terraform init -backend-config="bucket=<BUCKET_NAME>" -backend-config="key=<KEY>"
  backend "s3" {
    # bucket         - provided via init command
    # key            - provided via init command
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "cloud-native-devops-platform-terraform-locks"
  }
}

# ------------------------------------------------------------------------------
# AWS Provider
# ------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "cloud-native-devops-platform"
    }
  }
}

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cloud-native-devops-platform"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}
