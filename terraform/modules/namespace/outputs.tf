output "name" {
  description = "The created namespace's name, for other resources to depend on/reference."
  value       = kubernetes_namespace.this.metadata[0].name
}
