# ==============================================================================
# IAM Module
# ==============================================================================
# This module creates IAM roles and policies with:
# - Least-privilege access principles
# - Service roles for EKS, RDS, and other services
# - IRSA (IAM Roles for Service Accounts) configurations
# - Role-based access control for different teams
# - Permission boundaries for enhanced security
# - Cross-account access roles (if needed)
# ==============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ------------------------------------------------------------------------------
# EKS Admin Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "eks_admin" {
  name = "${var.project_name}-${var.environment}-eks-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      }
    ]
  })

  permissions_boundary = aws_iam_policy.permission_boundary.arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eks-admin"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy" "eks_admin" {
  name = "${var.project_name}-${var.environment}-eks-admin-policy"
  role = aws_iam_role.eks_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSFullAccess"
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2ReadAccess"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeRouteTables"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "eks.amazonaws.com",
              "ec2.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# EKS Developer Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "eks_developer" {
  name = "${var.project_name}-${var.environment}-eks-developer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      }
    ]
  })

  permissions_boundary = aws_iam_policy.permission_boundary.arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eks-developer"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy" "eks_developer" {
  name = "${var.project_name}-${var.environment}-eks-developer-policy"
  role = aws_iam_role.eks_developer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSReadAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:DescribeUpdate",
          "eks:ListUpdates",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# CI/CD Role for GitHub Actions
# ------------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.enable_github_actions_oidc ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4e98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-github-oidc"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role" "github_actions" {
  count = var.enable_github_actions_oidc ? 1 : 0

  name = "${var.project_name}-${var.environment}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions[0].arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/*:*"
          }
        }
      }
    ]
  })

  permissions_boundary = aws_iam_policy.permission_boundary.arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-github-actions"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy" "github_actions" {
  count = var.enable_github_actions_oidc ? 1 : 0

  name = "${var.project_name}-${var.environment}-github-actions-policy"
  role = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${var.project_name}-terraform-state-*",
          "arn:${data.aws_partition.current.partition}:s3:::${var.project_name}-terraform-state-*/*"
        ]
      },
      {
        Sid    = "DynamoDBLockAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-terraform-locks"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "s3.${data.aws_region.current.name}.amazonaws.com",
              "ecr.${data.aws_region.current.name}.amazonaws.com"
            ]
          }
        }
      },
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.project_name}-${var.environment}"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Permission Boundary
# ------------------------------------------------------------------------------

resource "aws_iam_policy" "permission_boundary" {
  name        = "${var.project_name}-${var.environment}-permission-boundary"
  description = "Permission boundary for ${var.project_name} ${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAllActionsWithinProject"
        Effect = "Allow"
        Action = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project_name
          }
        }
      },
      {
        Sid    = "DenyDangerousActions"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:DeleteAccountPasswordPolicy",
          "iam:UpdateAccountPasswordPolicy",
          "organizations:LeaveOrganization",
          "account:CloseAccount"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyUnTaggedResources"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "rds:CreateDBInstance",
          "s3:CreateBucket"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestTag/Project" = var.project_name
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-permission-boundary"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Read-Only Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "readonly" {
  name = "${var.project_name}-${var.environment}-readonly"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-readonly"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy" "readonly" {
  name = "${var.project_name}-${var.environment}-readonly-policy"
  role = aws_iam_role.readonly.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyAccess"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "rds:Describe*",
          "rds:List*",
          "s3:Get*",
          "s3:List*",
          "eks:Describe*",
          "eks:List*",
          "elasticache:Describe*",
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "logs:Describe*",
          "logs:Get*",
          "logs:List*",
          "iam:Get*",
          "iam:List*",
          "kms:Describe*",
          "kms:List*"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Cross-Account Access Role (Optional)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "cross_account" {
  count = var.cross_account_trusted_account_id != null ? 1 : 0

  name = "${var.project_name}-${var.environment}-cross-account"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${var.cross_account_trusted_account_id}:root"
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.cross_account_external_id
          }
        }
      }
    ]
  })

  permissions_boundary = aws_iam_policy.permission_boundary.arn
  max_session_duration = 3600

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-cross-account"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy" "cross_account" {
  count = var.cross_account_trusted_account_id != null ? 1 : 0

  name = "${var.project_name}-${var.environment}-cross-account-policy"
  role = aws_iam_role.cross_account[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyProjectResources"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
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
