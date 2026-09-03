variable "environment_name" {
  description = "Environment name (e.g. aws-production, aws-dr) - namespaces the smoke-test resource and its tags."
  type        = string
}

variable "aws_region" {
  description = "AWS region this environment targets - see ADR 0004 for the production/DR region pair (ap-southeast-3 / ap-southeast-1)."
  type        = string
}

# --- Floci wiring (ADR 0004's "validate before spend" principle) ---
#
# Points the `aws` provider at Floci instead of real AWS, so every later
# AWS ticket can be built and verified with zero real AWS spend. Dropped
# once a real cutover happens, in favor of the GitHub OIDC auth ADR 0007
# already commits to for CI -> real AWS. Floci's placeholder credentials
# are NOT a variable here on purpose - see providers.tf's comment; they're
# environment variables (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY) the AWS
# provider's default credential chain picks up on its own.

variable "floci_endpoint" {
  description = "Base URL of the local Floci AWS API emulator. Override with TF_VAR_floci_endpoint (see .env.local) if Floci isn't running on the default port."
  type        = string
  default     = "http://localhost:4566"
}
