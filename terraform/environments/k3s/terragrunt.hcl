# Phase -1 (../../README.md) — installs k3s itself. No dependencies: this is
# the first thing applied, before any provider needs a live kubeconfig.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Terragrunt always runs Terraform from a copied working directory, not this
# one in place. `source` points at `terraform/` (this environment's
# grandparent) with a `//environments/k3s` subdir selector, so the copy
# preserves `terraform/`'s whole tree — `modules/` included — meaning this
# environment's `../../modules/k3s` reference in main.tf still resolves
# inside the copy exactly as it does today. Pointing `source` at just this
# directory alone (without the shared `modules/` sibling) is what breaks
# that reference — learned by hitting it, not by design.
terraform {
  source = "${get_terragrunt_dir()}/../..//environments/k3s"
}
