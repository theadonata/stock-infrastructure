module "argocd" {
  source        = "../../modules/argocd"
  chart_version = var.argocd_chart_version
}

module "sealed_secrets" {
  source        = "../../modules/sealed-secrets"
  chart_version = var.sealed_secrets_chart_version
}
