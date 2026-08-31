# Same reasoning as the homelab modules' providers.tf, just for AWS:
# redirect every service call at Floci instead of real AWS so this
# validates and applies with zero real AWS spend. Floci doesn't run the
# STS/IAM identity checks real AWS does on provider startup, so those are
# skipped rather than left to fail against an emulator with no real
# account behind it.
provider "aws" {
  region = var.aws_region

  access_key = var.floci_access_key
  secret_key = var.floci_secret_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    # Only what this prefactor's smoke-test resource needs - later AWS
    # tickets add ec2/eks/rds/etc. entries here as they bring those
    # resources in.
    s3 = var.floci_endpoint
  }
}
