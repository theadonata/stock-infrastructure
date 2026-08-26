# Phase -1 (../../README.md) — installs k3s itself. No dependencies: this is
# the first thing applied, before any provider needs a live kubeconfig.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Terragrunt always runs Terraform from a copied working directory, not this
# one in place. `source` points at `terraform/` (this environment's
# grandparent) with a `//modules/k3s-environment` subdir selector, so the
# copy preserves `terraform/`'s whole tree — `modules/` included — meaning
# k3s-environment's own `../k3s` reference in its main.tf still resolves
# inside the copy exactly as it does today. Pointing `source` at just that
# module directory alone (without the shared `modules/k3s` sibling) is what
# breaks that reference — learned by hitting it, not by design.
terraform {
  source = "${get_terragrunt_dir()}/../..//modules/k3s-environment"
}
