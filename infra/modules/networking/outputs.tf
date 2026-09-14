output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Where internet-facing load balancers go"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "Where EKS nodes go"
  value       = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  description = "Where RDS goes"
  value       = aws_subnet.private_data[*].id
}

output "availability_zones" {
  value = var.availability_zones
}

output "nat_gateway_enabled" {
  description = "Whether the billable NAT gateway is currently running"
  value       = var.enable_nat_gateway
}
