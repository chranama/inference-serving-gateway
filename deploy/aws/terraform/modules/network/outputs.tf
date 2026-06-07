output "vpc_id" {
  description = "VPC identifier for the bounded AWS slice."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block for security-group and subnet consumers."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs in availability-zone order."
  value       = [for az in var.availability_zones : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs in availability-zone order."
  value       = [for az in var.availability_zones : aws_subnet.private[az].id]
}
