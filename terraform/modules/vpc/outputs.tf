output "vpc_id" {
  description = "ID of this environment's VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ - where a future ALB (ADR 0006) attaches, and half of the EKS cluster's vpc_config subnet_ids (modules/eks)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ - where the EKS node group and any future in-cluster-only resources (e.g. Aurora, ADR 0005) live."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "One NAT gateway per AZ (ADR 0006) - confirms the per-AZ egress isolation, not a single shared gateway."
  value       = aws_nat_gateway.this[*].id
}
