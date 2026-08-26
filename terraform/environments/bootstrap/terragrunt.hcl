# Phase 0 (../../README.md) — installs Argo CD + Sealed Secrets. Requires
# k3s's kubeconfig to already exist for the kubernetes/helm providers to
# configure against.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../k3s"]
}

# See ../k3s/terragrunt.hcl for why `source` must point at the shared
# `terraform/` parent (not this directory alone) with a `//environments/...`
# subdir selector — this environment's main.tf modules live under
# `../../modules/`, outside this directory, and need to be copied alongside
# it for Terragrunt's working-directory copy to resolve them.
terraform {
  source = "${get_terragrunt_dir()}/../..//environments/bootstrap"
}
