# ==============================================================================
# RDS PostgreSQL Module
# ==============================================================================
# This module creates a production-grade RDS PostgreSQL database with:
# - Multi-AZ deployment for high availability
# - KMS encryption for data at rest
# - Automated backups with configurable retention
# - Enhanced monitoring and CloudWatch alarms
# - Parameter groups for performance tuning
# - IAM database authentication support
# - Security group with least-privilege access
# - Secrets Manager integration for password management
# ==============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ------------------------------------------------------------------------------
# KMS Key for RDS Encryption
# ------------------------------------------------------------------------------

resource "aws_kms_key" "rds" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for RDS encryption (${var.project_name}-${var.environment})"
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
        Sid    = "Allow RDS Service"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
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
      Name        = "${var.project_name}-${var.environment}-rds-kms"
      Environment = var.environment
    }
  )
}

resource "aws_kms_alias" "rds" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.project_name}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds[0].key_id
}

# ------------------------------------------------------------------------------
# DB Subnet Group
# ------------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-rds"
  description = "Subnet group for ${var.project_name} ${var.environment} RDS"
  subnet_ids  = var.database_subnet_ids

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Security Group for RDS
# ------------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL access"
  vpc_id      = var.vpc_id

  # PostgreSQL port - allow from EKS nodes and bastion only
  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Additional ingress rules from specific security groups
  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      description              = "PostgreSQL from ${ingress.value}"
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      source_security_group_id = ingress.value
    }
  }

  # No outbound restrictions needed for RDS
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
      Name        = "${var.project_name}-${var.environment}-rds-sg"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# DB Parameter Group
# ------------------------------------------------------------------------------

resource "aws_db_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-postgres${replace(var.engine_version, ".", "")}"
  family      = "postgres${split(".", var.engine_version)[0]}"
  description = "Custom parameter group for ${var.project_name} ${var.environment}"

  # Performance tuning parameters
  parameter {
    name  = "max_connections"
    value = var.max_connections
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/32768}"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory/8192}"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "work_mem"
    value = "{DBInstanceClassMemory/131072}"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "{DBInstanceClassMemory/393216}"
    apply_method = "pending-reboot"
  }

  # Logging parameters
  parameter {
    name  = "log_min_duration_statement"
    value = var.slow_query_threshold_ms
    apply_method = "immediate"
  }

  parameter {
    name  = "log_connections"
    value = "1"
    apply_method = "immediate"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
    apply_method = "immediate"
  }

  parameter {
    name  = "log_checkpoints"
    value = "1"
    apply_method = "immediate"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
    apply_method = "immediate"
  }

  # Enable pg_stat_statements for query performance monitoring
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "pg_stat_statements.track"
    value = "all"
    apply_method = "pending-reboot"
  }

  # SSL enforcement
  parameter {
    name  = "rds.force_ssl"
    value = "1"
    apply_method = "pending-reboot"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-postgres-params"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Password Management
# ------------------------------------------------------------------------------

# Generate a random master password
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store password in Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}/${var.environment}/rds/master-password"
  description             = "Master password for ${var.project_name} ${var.environment} RDS"
  recovery_window_in_days = var.secret_recovery_window
  kms_key_id              = var.create_kms_key ? aws_kms_key.rds[0].arn : var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds-password"
      Environment = var.environment
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "postgresql"
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = var.database_name
  })
}

# ------------------------------------------------------------------------------
# RDS Instance
# ------------------------------------------------------------------------------

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}"

  # Engine configuration
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = var.create_kms_key ? aws_kms_key.rds[0].arn : var.kms_key_arn

  # Database configuration
  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result
  port     = 5432

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # High availability
  multi_az = var.multi_az

  # Parameter group
  parameter_group_name = aws_db_parameter_group.main.name

  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  # Monitoring
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs
  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? (var.create_kms_key ? aws_kms_key.rds[0].arn : var.kms_key_arn) : null
  performance_insights_retention_period = var.performance_insights_retention_period

  # Deletion protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot

  # IAM database authentication
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  # Auto minor version upgrade
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Copy tags to snapshots
  copy_tags_to_snapshot = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds"
      Environment = var.environment
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.rds_monitoring,
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [password]
  }
}

# ------------------------------------------------------------------------------
# Read Replicas (Optional)
# ------------------------------------------------------------------------------

resource "aws_db_instance" "read_replica" {
  count = var.read_replica_count

  identifier = "${var.project_name}-${var.environment}-rr-${count.index + 1}"

  # Replicate from source
  replicate_source_db = aws_db_instance.main.arn

  instance_class = var.read_replica_instance_class != null ? var.read_replica_instance_class : var.instance_class

  # Storage
  storage_encrypted = true
  kms_key_id        = var.create_kms_key ? aws_kms_key.rds[0].arn : var.kms_key_arn

  # Networking
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Parameter group
  parameter_group_name = aws_db_parameter_group.main.name

  # Monitoring
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs
  performance_insights_enabled    = var.performance_insights_enabled

  # Backup
  backup_retention_period = 0

  # Auto minor version upgrade
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Deletion
  skip_final_snapshot = var.skip_final_snapshot

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rr-${count.index + 1}"
      Environment = var.environment
      Type        = "read-replica"
    }
  )

  depends_on = [
    aws_db_instance.main,
  ]
}

# ------------------------------------------------------------------------------
# IAM Role for Enhanced Monitoring
# ------------------------------------------------------------------------------

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds-monitoring-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
  role       = aws_iam_role.rds_monitoring.name
}

# ------------------------------------------------------------------------------
# CloudWatch Alarms
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "RDS CPU utilization is high (${var.project_name}-${var.environment})"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds-cpu-alarm"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-low-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold_bytes
  alarm_description   = "RDS freeable memory is low (${var.project_name}-${var.environment})"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds-memory-alarm"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.connections_alarm_threshold
  alarm_description   = "RDS database connections are high (${var.project_name}-${var.environment})"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds-connections-alarm"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "storage_space" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.storage_alarm_threshold_bytes
  alarm_description   = "RDS free storage space is low (${var.project_name}-${var.environment})"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds-storage-alarm"
      Environment = var.environment
    }
  )
}
