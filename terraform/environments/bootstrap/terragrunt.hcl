# Phase 0 (../../README.md) — installs Argo CD + Sealed Secrets. Requires
# k3s's kubeconfig to already exist for the kubernetes/helm providers to
# configure against.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../k3s"]
}

# See ../dev/terragrunt.hcl for why `source` points at the shared
# `//modules/bootstrap-environment` subdir rather than a per-environment
# main.tf.
terraform {
  source = "${get_terragrunt_dir()}/../..//modules/bootstrap-environment"
}
