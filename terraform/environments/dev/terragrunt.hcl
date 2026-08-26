# Phase 1 (../../README.md) — dev namespace + automated-sync Argo CD
# Application. Requires bootstrap's Application CRD to already be
# registered in the cluster.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../bootstrap"]
}

# See ../k3s/terragrunt.hcl for why `source` must point at the shared
# `terraform/` parent (not this directory alone) with a `//environments/...`
# subdir selector — this environment's main.tf modules live under
# `../../modules/`, outside this directory, and need to be copied alongside
# it for Terragrunt's working-directory copy to resolve them.
terraform {
  source = "${get_terragrunt_dir()}/../..//environments/dev"
}
