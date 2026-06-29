# ==============================================================================
# Monitoring Module
# ==============================================================================
# This module creates a comprehensive monitoring stack with:
# - CloudWatch dashboards for infrastructure overview
# - CloudWatch alarms for critical metrics
# - SNS topics for alerting
# - Log groups with retention policies
# - Container Insights for EKS
# - Custom metrics and alarms
# - Integration points for Prometheus/Grafana
# ==============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# ------------------------------------------------------------------------------
# SNS Topic for Alerts
# ------------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  kms_master_key_id = var.kms_key_arn

  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget     = 1
        maxDelayTarget     = 60
        numRetries         = 3
        numMaxDelayRetries = 0
        numNoDelayRetries  = 0
        numMinDelayRetries = 0
        backoffFunction    = "exponential"
      }
      disableSubscriptionOverrides = false
      defaultThrottlePolicy = {
        maxReceivesPerSecond = 10
      }
    }
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-alerts"
      Environment = var.environment
    }
  )
}

# Email subscription (if provided)
resource "aws_sns_topic_subscription" "email" {
  count = length(var.alert_email_addresses)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email_addresses[count.index]
}

# PagerDuty subscription (if provided)
resource "aws_sns_topic_subscription" "pagerduty" {
  count = var.pagerduty_integration_endpoint != null ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.pagerduty_integration_endpoint
}

# ------------------------------------------------------------------------------
# CloudWatch Log Groups
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "application" {
  name              = "/${var.project_name}/${var.environment}/application"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-application-logs"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/${var.project_name}/${var.environment}/system"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-system-logs"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_log_group" "audit" {
  name              = "/${var.project_name}/${var.environment}/audit"
  retention_in_days = var.audit_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-audit-logs"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# CloudWatch Dashboard - Infrastructure Overview
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "infrastructure" {
  dashboard_name = "${var.project_name}-${var.environment}-infrastructure"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EKS Cluster - Node CPU Utilization"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ContainerInsights", "node_cpu_utilization", "ClusterName", "${var.project_name}-${var.environment}", { stat = "Average" }]
          ]
          period = 300
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EKS Cluster - Node Memory Utilization"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ContainerInsights", "node_memory_utilization", "ClusterName", "${var.project_name}-${var.environment}", { stat = "Average" }]
          ]
          period = 300
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "RDS - CPU Utilization"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "${var.project_name}-${var.environment}", { stat = "Average" }]
          ]
          period = 300
          annotations = {
            horizontal = [
              { value = 80, color = "#ff0000", label = "Critical" },
              { value = 60, color = "#ffa500", label = "Warning" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "RDS - Database Connections"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", "${var.project_name}-${var.environment}", { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "RDS - Free Storage Space"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBClusterIdentifier", "${var.project_name}-${var.environment}", { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "ALB - Request Count"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "${var.project_name}-${var.environment}", { stat = "Sum" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "ALB - Target Response Time"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "${var.project_name}-${var.environment}", { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "ALB - HTTP 5xx Errors"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", "${var.project_name}-${var.environment}", { stat = "Sum" }]
          ]
          period = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          title  = "Application Errors"
          region = data.aws_region.current.name
          query  = "SOURCE '/${var.project_name}/${var.environment}/application' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          region = data.aws_region.current.name
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# CloudWatch Alarms - EKS
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "eks_high_cpu" {
  count = var.create_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-eks-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_cpu_utilization"
  namespace           = "AWS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = var.eks_cpu_threshold
  alarm_description   = "EKS cluster CPU utilization is high (${var.project_name}-${var.environment})"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = "${var.project_name}-${var.environment}"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eks-cpu-alarm"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "eks_high_memory" {
  count = var.create_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-eks-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_memory_utilization"
  namespace           = "AWS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = var.eks_memory_threshold
  alarm_description   = "EKS cluster memory utilization is high (${var.project_name}-${var.environment})"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = "${var.project_name}-${var.environment}"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eks-memory-alarm"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# CloudWatch Alarms - ALB
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_high_5xx" {
  count = var.create_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-high-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  alarm_description   = "ALB 5xx errors are high (${var.project_name}-${var.environment})"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = "${var.project_name}-${var.environment}"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-alb-5xx-alarm"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "alb_high_response_time" {
  count = var.create_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  extended_statistic  = "p99"
  threshold           = var.alb_response_time_threshold
  alarm_description   = "ALB response time is high (${var.project_name}-${var.environment})"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = "${var.project_name}-${var.environment}"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-alb-response-time-alarm"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Container Insights (EKS)
# ------------------------------------------------------------------------------

resource "aws_eks_addon" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  cluster_name                = var.eks_cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = var.container_insights_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-container-insights"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# CloudWatch Log Insights Queries
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_query_definition" "error_analysis" {
  name = "${var.project_name}-${var.environment}/error-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.application.name,
    aws_cloudwatch_log_group.system.name,
  ]

  query_string = <<-EOF
    fields @timestamp, @message, @logStream
    | filter @message like /ERROR/ or @message like /Exception/ or @message like /FATAL/
    | parse @message "* * *" as timestamp, level, msg
    | stats count(*) as error_count by bin(5m)
    | sort error_count desc
  EOF
}

resource "aws_cloudwatch_query_definition" "slow_requests" {
  name = "${var.project_name}-${var.environment}/slow-requests"

  log_group_names = [
    aws_cloudwatch_log_group.application.name,
  ]

  query_string = <<-EOF
    fields @timestamp, @message
    | parse @message "* * * * * * * *" as ip, identity, userid, timestamp2, request, status, size, response_time
    | filter response_time > 1000
    | stats count(*) as slow_request_count, avg(response_time) as avg_response_time, max(response_time) as max_response_time by bin(5m)
    | sort slow_request_count desc
  EOF
}
