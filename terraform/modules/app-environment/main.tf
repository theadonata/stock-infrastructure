# Shared root module for the "namespace + Argo CD Application" shape used
# by dev, staging, and monitoring — those three environments' main.tf were
# byte-identical apart from the values passed in, so this replaces all
# three with one module, parameterized via Terragrunt `inputs` instead.
#
# Module block names (`namespace`, `argocd_app`) are kept identical to what
# each environment's own main.tf used to declare at root level — Terragrunt
# treats whatever `source` points at as the root config, so a caller whose
# terragrunt.hcl source is this directory gets the exact same
# `module.namespace.*`/`module.argocd_app.*` state addresses as before.
# That's what let this refactor happen without any `terraform state mv` —
# verified with `terragrunt plan` against dev/staging's real state.
module "namespace" {
  source = "../namespace"
  name   = var.namespace_name
}

module "argocd_app" {
  source                = "../argocd-application"
  app_name              = var.app_name
  destination_namespace = module.namespace.name
  repo_url              = var.repo_url
  target_revision       = var.target_revision
  chart_path            = var.chart_path
  values_files          = var.values_files
  secrets_path          = var.secrets_path
  automated_sync        = var.automated_sync
  prune                 = var.prune
  self_heal             = var.self_heal
  server_side_apply     = var.server_side_apply

  depends_on = [module.namespace]
}
