# ==============================================================================
# VPC Module - Outputs
# ==============================================================================

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the created VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "ARN of the created VPC"
  value       = aws_vpc.main.arn
}

# ------------------------------------------------------------------------------
# Subnet Outputs
# ------------------------------------------------------------------------------

output "public_subnet_ids" {
  description = "List of public subnet IDs (one per AZ)"
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (one per AZ) - for EKS worker nodes"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}

output "database_subnet_ids" {
  description = "List of database subnet IDs (one per AZ) - isolated for RDS/Redis"
  value       = aws_subnet.database[*].id
}

output "database_subnet_cidrs" {
  description = "List of database subnet CIDR blocks"
  value       = aws_subnet.database[*].cidr_block
}

# ------------------------------------------------------------------------------
# Availability Zone Outputs
# ------------------------------------------------------------------------------

output "availability_zones" {
  description = "List of availability zones used"
  value       = data.aws_availability_zones.available.names
}

# ------------------------------------------------------------------------------
# NAT Gateway Outputs
# ------------------------------------------------------------------------------

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "List of public IPs assigned to NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

# ------------------------------------------------------------------------------
# Route Table Outputs
# ------------------------------------------------------------------------------

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs (one per AZ)"
  value       = aws_route_table.private[*].id
}

output "database_route_table_id" {
  description = "ID of the database route table"
  value       = aws_route_table.database.id
}

# ------------------------------------------------------------------------------
# Internet Gateway Output
# ------------------------------------------------------------------------------

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

# ------------------------------------------------------------------------------
# Security Group Outputs
# ------------------------------------------------------------------------------

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group for VPC endpoints"
  value       = length(aws_security_group.vpc_endpoints) > 0 ? aws_security_group.vpc_endpoints[0].id : null
}

# ------------------------------------------------------------------------------
# VPC Endpoint Outputs
# ------------------------------------------------------------------------------

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC endpoint"
  value       = length(aws_vpc_endpoint.s3) > 0 ? aws_vpc_endpoint.s3[0].id : null
}

# ------------------------------------------------------------------------------
# Flow Log Outputs
# ------------------------------------------------------------------------------

output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log"
  value       = length(aws_flow_log.main) > 0 ? aws_flow_log.main[0].id : null
}

output "vpc_flow_log_group_name" {
  description = "Name of the CloudWatch Log Group for VPC Flow Logs"
  value       = length(aws_cloudwatch_log_group.vpc_flow_logs) > 0 ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}

# ------------------------------------------------------------------------------
# VPC Peering Outputs
# ------------------------------------------------------------------------------

output "vpc_peering_connection_id" {
  description = "ID of the VPC peering connection (if enabled)"
  value       = length(aws_vpc_peering_connection.main) > 0 ? aws_vpc_peering_connection.main[0].id : null
}
