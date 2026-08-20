output "argocd_namespace" {
  value = module.argocd.namespace
}

output "sealed_secrets_namespace" {
  value = module.sealed_secrets.namespace
}
