# AWS production tier (ADR 0004). STOCK-6 wired up Terragrunt + the aws
# provider against Floci; STOCK-7 (this) adds the real networking (ADR
# 0006 - VPC, one NAT gateway per AZ) and EKS cluster (ADR 0004 - "compute
# stays Kubernetes") into modules/aws-environment. Still zero real AWS
# spend - everything here still targets Floci, not a real account.
#
# Independent of the homelab environments (k3s/bootstrap/dev/staging/
# monitoring) and of aws-dr - nothing here needs either to exist first.
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
