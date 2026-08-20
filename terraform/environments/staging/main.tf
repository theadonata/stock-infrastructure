module "namespace" {
  source = "../../modules/namespace"
  name   = "stock-hpp-staging"
}

module "argocd_app" {
  source                = "../../modules/argocd-application"
  app_name              = "stock-hpp-staging"
  destination_namespace = module.namespace.name
  repo_url              = var.repo_url
  target_revision       = var.target_revision
  values_files          = ["values.yaml", "values-staging.yaml"]
  secrets_path          = "secrets/staging"
  # Staging is the human-gated leg (gitops-plan.md Phase 2): even after the
  # bump-staging CI job's PR is merged by hand, Argo CD does NOT auto-sync —
  # a second explicit action (Sync in the Argo CD UI/CLI) is required. This
  # is the deliberate environment-promotion gate, on top of the PR-merge gate.
  automated_sync = false

  depends_on = [module.namespace]
}
