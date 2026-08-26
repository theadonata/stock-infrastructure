# Root Terragrunt config for terraform/environments/*. Named `root.hcl`, not
# `terragrunt.hcl` — Terragrunt now warns that a root `terragrunt.hcl` is a
# deprecated anti-pattern (it collides with `find_in_parent_folders()`'s
# default target for a genuinely nested config).
#
# Each `environments/<env>/` is now just a terragrunt.hcl — no per-environment
# versions.tf/providers.tf/main.tf/variables.tf. Those moved into
# `../modules/{k3s,bootstrap,app}-environment/`, one shared root module per
# environment *shape* (dev/staging/monitoring all use `app-environment`,
# parameterized via each terragrunt.hcl's own `inputs` block, since they
# were byte-identical apart from the values passed in). This file exists so
# each environment's terragrunt.hcl has an `include` target, and so their
# `dependencies` blocks (ordering only, no output values consumed) drive
# `terragrunt run-all` in the same order ../README.md documents by hand:
# k3s -> bootstrap -> {dev, staging, monitoring}. The backend block below is
# the one thing every environment still needs generated identically (see
# below for why).
#
# See `../docs/adr/0007-aws-cicd-iac.md` for why AWS environments (once
# added under a sibling directory) use directory-per-environment Terragrunt
# rather than Terraform workspaces — this root file is the shared
# ancestor both the homelab and AWS environment trees will `include`.
#
# Terragrunt always runs Terraform from a copied working directory
# (`.terragrunt-cache/...`), never the real environment directory in place
# — confirmed by hitting it directly: an earlier version of this repo had
# each environment commit its own `backend.tf` with a relative-path
# `backend "local" { path = "terraform.tfstate" }`; under Terragrunt that
# silently configured a *new, empty* state file inside the cache copy
# instead of finding the real one, which would have made the next `apply`
# try to recreate every already-applied resource (k3s, Argo CD, namespaces,
# Applications) from scratch. This `generate` block is the fix and the
# only place `backend.tf` is defined now — an absolute path anchored to the
# real directory (`get_terragrunt_dir()`, evaluated per-child even though
# this block lives in the shared root, always resolves to the *including*
# child's own directory, not the cache copy), so every environment keeps
# reading and writing the exact same `terraform.tfstate` file it always
# has, regardless of where Terraform physically executes. Environments no
# longer carry their own `backend.tf` at all — Terragrunt is required to
# run these now, plain `terraform` in an environment directory has no
# backend configuration.
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    terraform {
      backend "local" {
        path = "${get_terragrunt_dir()}/terraform.tfstate"
      }
    }
  EOF
}
