output "namespace" {
  description = "Namespace the Sealed Secrets controller was installed into."
  value       = kubernetes_namespace.sealed_secrets.metadata[0].name
}
