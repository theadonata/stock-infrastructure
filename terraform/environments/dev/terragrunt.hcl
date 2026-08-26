# Phase 1 (../../README.md) — dev namespace + automated-sync Argo CD
# Application. Requires bootstrap's Application CRD to already be
# registered in the cluster.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../bootstrap"]
}

# Points directly at the shared app-environment module (also used by
# staging/monitoring) rather than a per-environment main.tf — see
# ../../modules/app-environment/main.tf's comment. Still needs the
# `//modules/app-environment` subdir-selector form (not this directory
# alone): the module's own `source = "../namespace"`/`"../argocd-application"`
# references are relative to modules/, so the whole `terraform/` parent has
# to be copied alongside it for Terragrunt's working-directory copy to
# resolve them.
terraform {
  source = "${get_terragrunt_dir()}/../..//modules/app-environment"
}

# Dev is the fully-automated leg of the pipeline (gitops-plan.md Phase 1):
# every merge to main flows straight through to a running dev deployment
# with zero human steps once the bump-dev CI job's PR auto-merges.
inputs = {
  namespace_name = "stock-hpp-dev"
  app_name       = "stock-hpp-dev"
  values_files   = ["values.yaml", "values-dev.yaml"]
  secrets_path   = "secrets/dev"
  automated_sync = true
  prune          = true
  self_heal      = true
}
