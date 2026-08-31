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
# Floci is a local, free AWS API emulator. These three variables point the
# `aws` provider at it instead of real AWS, so every later AWS ticket can
# be built and verified with zero real AWS spend. They are dropped once a
# real cutover happens, in favor of the GitHub OIDC auth ADR 0007 already
# commits to for CI -> real AWS.

variable "floci_endpoint" {
  description = "Base URL of the local Floci AWS API emulator. Override with TF_VAR_floci_endpoint (see .env.local) if Floci isn't running on the default port."
  type        = string
  default     = "http://localhost:4566"
}

variable "floci_access_key" {
  description = "Placeholder credential Floci expects to see present - it does not perform real authentication. Never a real AWS access key. No default on purpose (a committed credential-shaped literal, even a fake one, is a static-analysis finding) - set via TF_VAR_floci_access_key, e.g. in .env.local."
  type        = string
}

variable "floci_secret_key" {
  description = "Placeholder credential Floci expects to see present - it does not perform real authentication. Never a real AWS secret key. No default on purpose (a committed credential-shaped literal, even a fake one, is a static-analysis finding) - set via TF_VAR_floci_secret_key, e.g. in .env.local."
  type        = string
  sensitive   = true
}
