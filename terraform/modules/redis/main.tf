# ==============================================================================
# ElastiCache Redis Module
# ==============================================================================
# This module creates a production-grade ElastiCache Redis cluster with:
# - Cluster mode enabled for horizontal scaling
# - Multi-AZ with auto-failover for high availability
# - KMS encryption for data at rest
# - Encryption in transit (TLS)
# - Automatic failover enabled
# - Parameter group for performance tuning
# - CloudWatch alarms for monitoring
# - Security group with least-privilege access
# - Snapshot backups with configurable retention
# ==============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ------------------------------------------------------------------------------
# KMS Key for Redis Encryption
# ------------------------------------------------------------------------------

resource "aws_kms_key" "redis" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for ElastiCache Redis encryption (${var.project_name}-${var.environment})"
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
        Sid    = "Allow ElastiCache Service"
        Effect = "Allow"
        Principal = {
          Service = "elasticache.amazonaws.com"
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
      Name        = "${var.project_name}-${var.environment}-redis-kms"
      Environment = var.environment
    }
  )
}

resource "aws_kms_alias" "redis" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.project_name}-${var.environment}-redis"
  target_key_id = aws_kms_key.redis[0].key_id
}

# ------------------------------------------------------------------------------
# Subnet Group
# ------------------------------------------------------------------------------

resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-redis"
  description = "Subnet group for ${var.project_name} ${var.environment} Redis"
  subnet_ids  = var.database_subnet_ids

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Security Group for Redis
# ------------------------------------------------------------------------------

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Security group for ElastiCache Redis access"
  vpc_id      = var.vpc_id

  # Redis port - allow from VPC only
  ingress {
    description = "Redis from VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Additional ingress from specific security groups
  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      description              = "Redis from ${ingress.value}"
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      source_security_group_id = ingress.value
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis-sg"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Parameter Group
# ------------------------------------------------------------------------------

resource "aws_elasticache_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-redis${replace(var.engine_version, ".", "")}"
  family      = "redis${var.parameter_group_family}"
  description = "Custom parameter group for ${var.project_name} ${var.environment}"

  # Memory management
  parameter {
    name  = "maxmemory-policy"
    value = var.maxmemory_policy
  }

  # Slow log
  parameter {
    name  = "slowlog-log-slower-than"
    value = var.slowlog_log_slower_than
  }

  parameter {
    name  = "slowlog-max-len"
    value = var.slowlog_max_len
  }

  # TCP keepalive
  parameter {
    name  = "tcp-keepalive"
    value = var.tcp_keepalive
  }

  # Timeout
  parameter {
    name  = "timeout"
    value = var.client_timeout
  }

  # Disable dangerous commands in production
  dynamic "parameter" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      name  = "rename-command"
      value = "FLUSHALL \"\""
    }
  }

  dynamic "parameter" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      name  = "rename-command"
      value = "FLUSHDB \"\""
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis-params"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Replication Group (Redis Cluster)
# ------------------------------------------------------------------------------

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project_name}-${var.environment}"
  description          = "Redis cluster for ${var.project_name} ${var.environment}"

  # Engine configuration
  engine             = "redis"
  engine_version     = var.engine_version
  node_type          = var.node_type
  port               = 6379
  parameter_group_name = aws_elasticache_parameter_group.main.name

  # Cluster mode configuration
  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  # Encryption
  at_rest_encryption_enabled  = true
  kms_key_id                  = var.create_kms_key ? aws_kms_key.redis[0].arn : var.kms_key_arn
  transit_encryption_enabled  = var.transit_encryption_enabled
  transit_encryption_mode     = var.transit_encryption_mode
  auth_token                  = var.transit_encryption_enabled ? random_password.auth_token[0].result : null

  # Networking
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # Snapshot configuration
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window
  final_snapshot_identifier = var.final_snapshot_identifier

  # Maintenance
  maintenance_window          = var.maintenance_window
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  apply_immediately           = var.apply_immediately

  # Logging
  dynamic "log_delivery_configuration" {
    for_each = var.enable_slow_log ? [1] : []
    content {
      destination      = aws_cloudwatch_log_group.redis_slow[0].name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "slow-log"
    }
  }

  dynamic "log_delivery_configuration" {
    for_each = var.enable_engine_log ? [1] : []
    content {
      destination      = aws_cloudwatch_log_group.redis_engine[0].name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "engine-log"
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis"
      Environment = var.environment
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------------------------
# Auth Token for Transit Encryption
# ------------------------------------------------------------------------------

resource "random_password" "auth_token" {
  count = var.transit_encryption_enabled ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
}

# Store auth token in Secrets Manager
resource "aws_secretsmanager_secret" "redis_auth" {
  count = var.transit_encryption_enabled ? 1 : 0

  name                    = "${var.project_name}/${var.environment}/redis/auth-token"
  description             = "Auth token for ${var.project_name} ${var.environment} Redis"
  recovery_window_in_days = var.secret_recovery_window
  kms_key_id              = var.create_kms_key ? aws_kms_key.redis[0].arn : var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis-auth"
      Environment = var.environment
    }
  )
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  count = var.transit_encryption_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.redis_auth[0].id
  secret_string = jsonencode({
    host       = aws_elasticache_replication_group.main.primary_endpoint_address
    port       = 6379
    auth_token = random_password.auth_token[0].result
  })
}

# ------------------------------------------------------------------------------
# CloudWatch Log Groups
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "redis_slow" {
  count = var.enable_slow_log ? 1 : 0

  name              = "/aws/elasticache/${var.project_name}-${var.environment}/slow-log"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis-slow-log"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_log_group" "redis_engine" {
  count = var.enable_engine_log ? 1 : 0

  name              = "/aws/elasticache/${var.project_name}-${var.environment}/engine-log"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis-engine-log"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# CloudWatch Alarms
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-redis-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "Redis CPU utilization is high (${var.project_name}-${var.environment})"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.replication_group_id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis-cpu-alarm"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "memory_utilization" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-redis-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold
  alarm_description   = "Redis memory usage is high (${var.project_name}-${var.environment})"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.replication_group_id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis-memory-alarm"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "connections" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-redis-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CurrConnections"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.connections_alarm_threshold
  alarm_description   = "Redis connections are high (${var.project_name}-${var.environment})"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.replication_group_id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis-connections-alarm"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "evictions" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-redis-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Sum"
  threshold           = var.evictions_alarm_threshold
  alarm_description   = "Redis evictions detected (${var.project_name}-${var.environment})"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.replication_group_id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-redis-evictions-alarm"
      Environment = var.environment
    }
  )
}
