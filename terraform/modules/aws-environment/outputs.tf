output "vpc_id" {
  description = "ID of this environment's VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ - where a future ALB (ADR 0006) attaches."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ - where the EKS node group and any future in-cluster-only resources (e.g. Aurora, ADR 0005) live."
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "One NAT gateway per AZ (ADR 0006) - confirms the per-AZ egress isolation, not a single shared gateway."
  value       = module.vpc.nat_gateway_ids
}

output "eks_cluster_name" {
  description = "EKS cluster name - what kubectl/aws eks update-kubeconfig and Argo CD's cluster registration both need."
  value       = module.eks.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.eks_cluster_endpoint
}

output "eks_cluster_certificate_authority" {
  description = "Base64-encoded cluster CA certificate, for kubeconfig generation."
  value       = module.eks.eks_cluster_certificate_authority
}
