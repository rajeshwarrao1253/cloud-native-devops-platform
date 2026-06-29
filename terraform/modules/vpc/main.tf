# ==============================================================================
# VPC Networking Module
# ==============================================================================
# This module creates a production-grade VPC with:
# - Multi-AZ public and private subnets
# - NAT Gateways per AZ for high availability
# - VPC Flow Logs for network monitoring
# - VPC Endpoints for AWS services (reduces NAT Gateway costs)
# - Network ACLs and Security Groups
# - Internet Gateway for public subnet access
# ==============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Fetch available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"

  # Exclude Local Zones to ensure we only get traditional AZs
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# ------------------------------------------------------------------------------
# VPC
# ------------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  # Instance tenancy - dedicated for compliance requirements
  instance_tenancy = var.dedicated_tenancy ? "dedicated" : "default"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpc"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# DHCP Options Set
# ------------------------------------------------------------------------------

resource "aws_vpc_dhcp_options" "main" {
  domain_name         = "${var.environment}.${var.project_name}.local"
  domain_name_servers = ["AmazonProvidedDNS"]
  ntp_servers         = ["169.254.169.123"] # Amazon Time Sync Service

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-dhcp"
      Environment = var.environment
    }
  )
}

resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.main.id
}

# ------------------------------------------------------------------------------
# Internet Gateway
# ------------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-igw"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Subnets
# ------------------------------------------------------------------------------

# Public subnets - one per AZ
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  # Enable auto-assign IPv6 if needed
  # assign_ipv6_address_on_creation = var.enable_ipv6

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-public-${data.aws_availability_zones.available.names[count.index]}"
      Environment = var.environment
      Type        = "public"
      # Required for Kubernetes ALB ingress controller auto-discovery
      "kubernetes.io/role/elb"                       = "1"
      "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Private subnets - one per AZ (for EKS worker nodes)
resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + var.az_count)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-private-${data.aws_availability_zones.available.names[count.index]}"
      Environment = var.environment
      Type        = "private"
      # Required for Kubernetes internal ALB auto-discovery
      "kubernetes.io/role/internal-elb"             = "1"
      "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Database subnets - one per AZ (isolated, no NAT access)
resource "aws_subnet" "database" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + (var.az_count * 2))
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-database-${data.aws_availability_zones.available.names[count.index]}"
      Environment = var.environment
      Type        = "database"
    }
  )
}

# ------------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
# ------------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count = var.single_nat_gateway ? 1 : var.az_count

  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
      Environment = var.environment
    }
  )

  depends_on = [aws_internet_gateway.main]

  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------------------------
# NAT Gateways
# ------------------------------------------------------------------------------

resource "aws_nat_gateway" "main" {
  count = var.single_nat_gateway ? 1 : var.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-nat-gw-${count.index + 1}"
      Environment = var.environment
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# ------------------------------------------------------------------------------
# Route Tables
# ------------------------------------------------------------------------------

# Public route table - routes all traffic through IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-public-rt"
      Environment = var.environment
      Type        = "public"
    }
  )
}

# Private route tables - one per AZ, routes through NAT Gateway
resource "aws_route_table" "private" {
  count = var.az_count

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}"
      Environment = var.environment
      Type        = "private"
    }
  )
}

# Database route tables - no internet access, local only
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-database-rt"
      Environment = var.environment
      Type        = "database"
    }
  )
}

# ------------------------------------------------------------------------------
# Route Table Associations
# ------------------------------------------------------------------------------

# Public subnet associations
resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnet associations
resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Database subnet associations
resource "aws_route_table_association" "database" {
  count = var.az_count

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# ------------------------------------------------------------------------------
# VPC Flow Logs
# ------------------------------------------------------------------------------

# CloudWatch Log Group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.project_name}-${var.environment}-flow-logs"
  retention_in_days = var.flow_logs_retention_days

  kms_key_id = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpc-flow-logs"
      Environment = var.environment
    }
  )
}

# IAM Role for VPC Flow Logs
resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  name = "${var.project_name}-${var.environment}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpc-flow-logs-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  name = "${var.project_name}-${var.environment}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  iam_role_arn             = aws_iam_role.vpc_flow_logs[0].arn
  log_format               = var.flow_log_format
  max_aggregation_interval = 60

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-flow-log"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# VPC Endpoints (reduces NAT Gateway costs and improves security)
# ------------------------------------------------------------------------------

# S3 Gateway Endpoint (free, does not use NAT Gateway)
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.database.id]
  )

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-s3-endpoint"
      Environment = var.environment
    }
  )
}

# DynamoDB Gateway Endpoint
resource "aws_vpc_endpoint" "dynamodb" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.database.id]
  )

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-dynamodb-endpoint"
      Environment = var.environment
    }
  )
}

# ECR API Interface Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-ecr-api-endpoint"
      Environment = var.environment
    }
  )
}

# ECR DKR Interface Endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-ecr-dkr-endpoint"
      Environment = var.environment
    }
  )
}

# CloudWatch Logs Interface Endpoint
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-cloudwatch-logs-endpoint"
      Environment = var.environment
    }
  )
}

# SSM Interface Endpoint
resource "aws_vpc_endpoint" "ssm" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-ssm-endpoint"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Security Groups
# ------------------------------------------------------------------------------

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0

  name        = "${var.project_name}-${var.environment}-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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
      Name        = "${var.project_name}-${var.environment}-vpc-endpoints-sg"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# Network ACLs
# ------------------------------------------------------------------------------

# Public subnet NACL
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  # Allow inbound HTTP
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow inbound HTTPS
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow inbound ephemeral ports (for return traffic)
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow outbound HTTP
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow outbound HTTPS
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow outbound ephemeral ports
  egress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-public-nacl"
      Environment = var.environment
    }
  )
}

# Private subnet NACL
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # Allow inbound from VPC
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Allow outbound to VPC
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Allow outbound HTTPS (through NAT)
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-private-nacl"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# VPC Peering (Optional)
# ------------------------------------------------------------------------------

resource "aws_vpc_peering_connection" "main" {
  count = var.vpc_peering_enabled ? 1 : 0

  vpc_id        = aws_vpc.main.id
  peer_vpc_id   = var.peer_vpc_id
  peer_owner_id = var.peer_owner_id
  peer_region   = var.peer_region
  auto_accept   = var.peer_owner_id == data.aws_caller_identity.current.account_id

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-peer"
      Environment = var.environment
    }
  )
}

# ------------------------------------------------------------------------------
# VPC Peering Routes (Optional)
# ------------------------------------------------------------------------------

resource "aws_route" "peering" {
  count = var.vpc_peering_enabled ? 1 : 0

  route_table_id            = aws_route_table.private[0].id
  destination_cidr_block    = var.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main[0].id
}
