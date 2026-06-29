# ==============================================================================
# S3 and CloudFront Module
# ==============================================================================
# This module creates a production-grade S3 and CloudFront setup with:
# - S3 buckets with versioning and MFA delete
# - Server-side encryption with KMS
# - Lifecycle policies for cost optimization
# - Public access blocking
# - CloudFront distribution with OAI
# - WAF integration for security
# - Access logging
# - CORS configuration
# ==============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ------------------------------------------------------------------------------
# KMS Key for S3 Encryption
# ------------------------------------------------------------------------------

resource "aws_kms_key" "s3" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for S3 encryption (${var.project_name}-${var.environment})"
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
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow CloudFront"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-s3-kms"
      Environment = var.environment
    }
  )
}

resource "aws_kms_alias" "s3" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.project_name}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3[0].key_id
}

# ------------------------------------------------------------------------------
# S3 Bucket - Main Assets
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "main" {
  bucket = "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-assets"
      Environment = var.environment
    }
  )
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.create_kms_key ? aws_kms_key.s3[0].arn : var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# Versioning
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Suspended"
    mfa_delete = var.enable_mfa_delete ? "Enabled" : "Disabled"
  }
}

# Lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  # Transition current versions to cheaper storage
  rule {
    id     = "transition-current-versions"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
  }

  # Expire non-current versions
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Abort incomplete multipart uploads
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Expire old logs
  dynamic "rule" {
    for_each = var.logs_expiration_days != null ? [1] : []
    content {
      id     = "expire-logs"
      status = "Enabled"
      filter {
        prefix = "logs/"
      }
      expiration {
        days = var.logs_expiration_days
      }
    }
  }
}

# CORS configuration
resource "aws_s3_bucket_cors_configuration" "main" {
  count = var.enable_cors ? 1 : 0

  bucket = aws_s3_bucket.main.id

  cors_rule {
    allowed_headers = var.cors_allowed_headers
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers  = var.cors_expose_headers
    max_age_seconds = var.cors_max_age_seconds
  }
}

# Bucket policy - allow CloudFront access
resource "aws_s3_bucket_policy" "main" {
  count = var.enable_cloudfront ? 1 : 0

  bucket = aws_s3_bucket.main.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAI"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.main.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main[0].arn
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.main,
  ]
}

# ------------------------------------------------------------------------------
# S3 Bucket - Logging
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = "${var.project_name}-${var.environment}-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-logs"
      Environment = var.environment
    }
  )
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = var.logs_retention_days
    }
  }
}

# ------------------------------------------------------------------------------
# S3 Bucket - Terraform State (if creating state bucket)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "terraform_state" {
  count = var.create_terraform_state_bucket ? 1 : 0

  bucket = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-terraform-state"
      Environment = var.environment
    }
  )
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  count = var.create_terraform_state_bucket ? 1 : 0

  bucket = aws_s3_bucket.terraform_state[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  count = var.create_terraform_state_bucket ? 1 : 0

  bucket = aws_s3_bucket.terraform_state[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.create_kms_key ? aws_kms_key.s3[0].arn : var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  count = var.create_terraform_state_bucket ? 1 : 0

  bucket = aws_s3_bucket.terraform_state[0].id

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Enabled"
  }
}

# ------------------------------------------------------------------------------
# CloudFront Origin Access Identity
# ------------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_identity" "main" {
  count = var.enable_cloudfront ? 1 : 0

  comment = "OAI for ${var.project_name} ${var.environment}"
}

# ------------------------------------------------------------------------------
# CloudFront Distribution
# ------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "main" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} ${var.environment} CDN"
  default_root_object = var.default_root_object
  price_class         = var.cloudfront_price_class
  wait_for_deployment = false

  # Origin - S3 bucket
  origin {
    domain_name = aws_s3_bucket.main.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.main.bucket}"

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/${aws_cloudfront_origin_access_identity.main[0].id}"
    }
  }

  # Origin - API Gateway (if configured)
  dynamic "origin" {
    for_each = var.api_gateway_domain != null ? [1] : []
    content {
      domain_name = var.api_gateway_domain
      origin_id   = "API-Gateway"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }

      custom_header {
        name  = "X-Origin-Verify"
        value = var.origin_verify_header
      }
    }
  }

  # Default cache behavior - S3
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.main.bucket}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = var.min_ttl
    default_ttl            = var.default_ttl
    max_ttl                = var.max_ttl
    compress               = true
  }

  # API cache behavior (if configured)
  dynamic "ordered_cache_behavior" {
    for_each = var.api_gateway_domain != null ? [1] : []
    content {
      path_pattern     = "/api/*"
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "API-Gateway"

      forwarded_values {
        query_string = true
        headers      = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
        cookies {
          forward = "all"
        }
      }

      viewer_protocol_policy = "https-only"
      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 86400
    }
  }

  # Logging
  dynamic "logging_config" {
    for_each = var.enable_access_logging ? [1] : []
    content {
      include_cookies = false
      bucket          = aws_s3_bucket.logs[0].bucket_domain_name
      prefix          = "cloudfront/"
    }
  }

  # SSL certificate
  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != null ? "TLSv1.2_2021" : "TLSv1"
  }

  # Geo restrictions
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  # WAF Web ACL (if configured)
  web_acl_id = var.waf_web_acl_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-cdn"
      Environment = var.environment
    }
  )

  depends_on = [
    aws_s3_bucket.main,
  ]
}
