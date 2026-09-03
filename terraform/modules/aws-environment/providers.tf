# Same reasoning as the homelab modules' providers.tf, just for AWS:
# redirect every service call at Floci instead of real AWS so this
# validates and applies with zero real AWS spend. Floci doesn't run the
# STS/IAM identity checks real AWS does on provider startup, so those are
# skipped rather than left to fail against an emulator with no real
# account behind it.
#
# Deliberately no access_key/secret_key attributes here - static
# credential attributes on an aws provider block are a security-sensitive
# pattern static analysis flags regardless of whether the value is a
# literal or a variable reference. The AWS provider's default credential
# chain already picks up AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY from the
# environment (see .env.local), which Floci needs present but never
# validates - same env-var-only approach LocalStack-style emulators expect.
provider "aws" {
  region = var.aws_region

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
