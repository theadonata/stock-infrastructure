variable "environment_name" {
  description = "Environment name (e.g. aws-production, aws-dr) - namespaces every resource in this module and its tags."
  type        = string
}

variable "aws_region" {
  description = "AWS region this environment targets - see ADR 0004 for the production/DR region pair (ap-southeast-3 / ap-southeast-1)."
  type        = string
}

# --- Networking (STOCK-7, ADR 0006) ---

variable "vpc_cidr" {
  description = "CIDR block for this environment's VPC. Sized /16 so the /20 subnets carved out in vpc.tf (one public + one private per AZ) never collide even at az_count's max."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread the VPC (and one NAT gateway per AZ, per ADR 0006) across. Kept below every AZ a region might have on purpose - not all regions expose the same count, and Floci itself only emulates a fixed set."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4 - the vpc.tf subnet CIDR math (a /20 per AZ out of a /16) assumes it stays in this range."
  }
}

# --- EKS (STOCK-7, ADR 0004 "compute stays Kubernetes") ---

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS control plane. Pinned rather than left floating - see terraform/README.md's \"Provider versions\" note on why this project pins deliberately."
  type        = string
  default     = "1.31"
}

variable "eks_endpoint_public_access" {
  description = "Whether the EKS API server endpoint is reachable from outside the VPC. Defaults to false (private-only) as the secure default; a real cutover needs either a bastion/VPN into the VPC or setting this true together with eks_public_access_cidrs scoped to a known operator IP - never left open to 0.0.0.0/0."
  type        = bool
  default     = false
}

variable "eks_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the EKS public endpoint when eks_endpoint_public_access is true. Ignored (and left empty) otherwise - see that variable's description."
  type        = list(string)
  default     = []
}

variable "eks_node_instance_types" {
  description = "Instance types for the managed node group's launch template, in preference order."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_desired_size" {
  description = "Desired worker node count. Small on purpose - this is a single-app cluster (stock-hpp), not a shared multi-tenant one; scale via terragrunt inputs per environment if aws-production and aws-dr ever need to diverge."
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Lower bound for the managed node group's own scaling (not cluster-autoscaler - none is wired up yet)."
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Upper bound for the managed node group's own scaling (not cluster-autoscaler - none is wired up yet)."
  type        = number
  default     = 3
}

variable "eks_node_volume_size_gb" {
  description = "Root EBS volume size (GB) for each worker node."
  type        = number
  default     = 50
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
