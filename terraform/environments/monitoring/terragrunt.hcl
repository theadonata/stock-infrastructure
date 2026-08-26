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

# See ../k3s/terragrunt.hcl for why `source` must point at the shared
# `terraform/` parent (not this directory alone) with a `//environments/...`
# subdir selector — this environment's main.tf modules live under
# `../../modules/`, outside this directory, and need to be copied alongside
# it for Terragrunt's working-directory copy to resolve them.
terraform {
  source = "${get_terragrunt_dir()}/../..//environments/monitoring"
}
