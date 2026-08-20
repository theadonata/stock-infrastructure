module "namespace" {
  source = "../../modules/namespace"
  name   = "stock-hpp-dev"
}

module "argocd_app" {
  source                = "../../modules/argocd-application"
  app_name              = "stock-hpp-dev"
  destination_namespace = module.namespace.name
  repo_url              = var.repo_url
  target_revision       = var.target_revision
  values_files          = ["values.yaml", "values-dev.yaml"]
  secrets_path          = "secrets/dev"
  # Dev is the fully-automated leg of the pipeline (gitops-plan.md Phase 1):
  # every merge to main flows straight through to a running dev deployment
  # with zero human steps once the bump-dev CI job's PR auto-merges.
  automated_sync = true
  prune          = true
  self_heal      = true

  depends_on = [module.namespace]
}
