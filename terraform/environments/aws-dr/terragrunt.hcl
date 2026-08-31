# AWS DR (disaster-recovery) tier (ADR 0004). STOCK-6 prefactor scaffolding
# only - see ../aws-production/terragrunt.hcl for the full rationale, which
# applies identically here (same module, different region/environment
# inputs).
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_terragrunt_dir()}/../..//modules/aws-environment"
}

inputs = {
  environment_name = "aws-dr"
  aws_region        = "ap-southeast-1" # Singapore - low-latency APAC pairing, see ADR 0004
}
