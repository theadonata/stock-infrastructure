module "namespace" {
  source = "../../modules/namespace"
  name   = "monitoring"
}

module "argocd_app" {
  source                = "../../modules/argocd-application"
  app_name              = "monitoring"
  destination_namespace = module.namespace.name
  repo_url              = var.repo_url
  target_revision       = var.target_revision
  chart_path            = "charts/monitoring"
  values_files          = ["values.yaml"]
  # secrets_path deliberately left unset — charts/monitoring/templates/
  # carries its own SealedSecrets, so this renders as a single-source
  # Application. See docs/adr/0003-observability-stack.md.
  #
  # Automated, self-healing sync: this stack isn't gated behind the
  # dev->staging app-promotion flow (gitops-plan.md) the way stock-hpp is —
  # it's shared infrastructure both environments depend on, so every merge
  # to main rolls out immediately, the same as dev's Application.
  automated_sync = true
  prune          = true
  self_heal      = true

  depends_on = [module.namespace]
}
