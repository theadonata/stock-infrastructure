# Phase 2 (../../README.md) — staging namespace + manual-sync Argo CD
# Application. Requires bootstrap's Application CRD to already be
# registered in the cluster.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../bootstrap"]
}

# See ../dev/terragrunt.hcl for why `source` points at the shared
# `//modules/app-environment` subdir rather than a per-environment main.tf.
terraform {
  source = "${get_terragrunt_dir()}/../..//modules/app-environment"
}

# Staging is the human-gated leg (gitops-plan.md Phase 2): even after the
# bump-staging CI job's PR is merged by hand, Argo CD does NOT auto-sync —
# a second explicit action (Sync in the Argo CD UI/CLI) is required. This
# is the deliberate environment-promotion gate, on top of the PR-merge gate.
inputs = {
  namespace_name = "stock-hpp-staging"
  app_name       = "stock-hpp-staging"
  values_files   = ["values.yaml", "values-staging.yaml"]
  secrets_path   = "secrets/staging"
  automated_sync = false
}
