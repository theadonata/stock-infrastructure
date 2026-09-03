# AWS production tier (ADR 0004). STOCK-6 prefactor scaffolding only:
# wires up Terragrunt + the aws provider against Floci so every later AWS
# ticket (EKS, Aurora Global, networking, observability - ADRs 0005-0008)
# has a proven `terragrunt plan/apply` path to build on, with zero real
# AWS spend, instead of each one re-deriving provider config from scratch.
#
# Independent of the homelab environments (k3s/bootstrap/dev/staging/
# monitoring) and of aws-dr - nothing here needs either to exist first
# (STOCK-6: "Blocked by: None").
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_terragrunt_dir()}/../..//modules/aws-environment"
}

inputs = {
  environment_name = "aws-production"
  aws_region       = "ap-southeast-3" # Jakarta - keeps data in-country, see ADR 0004
}
