# Root module for environments/bootstrap — installs the cluster-wide
# controllers (Argo CD, Sealed Secrets) that dev/staging/monitoring depend
# on. Module block names (`argocd`, `sealed_secrets`) kept identical to
# what environments/bootstrap/main.tf used to declare at root level, so
# state addresses are unchanged by this move — see
# ../app-environment/main.tf's comment for why that matters.
module "argocd" {
  source        = "../argocd"
  chart_version = var.argocd_chart_version
}

module "sealed_secrets" {
  source        = "../sealed-secrets"
  chart_version = var.sealed_secrets_chart_version
}
