output "eks_cluster_name" {
  description = "EKS cluster name - what kubectl/aws eks update-kubeconfig and Argo CD's cluster registration both need."
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "eks_cluster_certificate_authority" {
  description = "Base64-encoded cluster CA certificate, for kubeconfig generation."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}
