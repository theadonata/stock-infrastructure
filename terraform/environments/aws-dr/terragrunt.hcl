# AWS DR (disaster-recovery) tier (ADR 0004) - see
# ../aws-production/terragrunt.hcl for the full rationale, which applies
# identically here (same module, different region/environment inputs).
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_terragrunt_dir()}/../..//modules/aws-environment"
}

inputs = {
  environment_name = "aws-dr"
  aws_region       = "ap-southeast-1" # Singapore - low-latency APAC pairing, see ADR 0004

  # Non-overlapping with aws-production's default (10.0.0.0/16) on purpose,
  # ahead of actually needing it: ADR 0005's Aurora Global failover will
  # need VPC peering or a Transit Gateway between the two regions, and
  # overlapping CIDRs would make that a much bigger fix later than setting
  # this now.
  vpc_cidr = "10.1.0.0/16"
}
