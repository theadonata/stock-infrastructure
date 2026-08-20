output "namespace" {
  description = "Namespace Argo CD was installed into, for argocd-application modules to target."
  value       = kubernetes_namespace.argocd.metadata[0].name
}
