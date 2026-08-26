# The monitoring namespace + single-source Argo CD Application (see
# ../../../docs/adr/0003-observability-stack.md). Not phased like dev/staging
# (../../README.md) — one shared instance, so this only depends on bootstrap,
# not on dev or staging existing first.
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

# secrets_path deliberately left unset — charts/monitoring/templates/
# carries its own SealedSecrets, so this renders as a single-source
# Application. See docs/adr/0003-observability-stack.md.
#
# Automated, self-healing sync: this stack isn't gated behind the
# dev->staging app-promotion flow (gitops-plan.md) the way stock-hpp is —
# it's shared infrastructure both environments depend on, so every merge
# to main rolls out immediately, the same as dev's Application.
inputs = {
  namespace_name = "monitoring"
  app_name       = "monitoring"
  chart_path     = "charts/monitoring"
  values_files   = ["values.yaml"]
  automated_sync = true
  prune          = true
  self_heal      = true
}
