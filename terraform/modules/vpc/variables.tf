variable "environment_name" {
  description = "Environment name (e.g. aws-production, aws-dr) - namespaces every resource in this module and its tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for this environment's VPC. Sized /16 so the /20 subnets carved out below (one public + one private per AZ) never collide even at az_count's max."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread the VPC (and one NAT gateway per AZ, per ADR 0006) across. Kept below every AZ a region might have on purpose - not all regions expose the same count, and Floci itself only emulates a fixed set."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4 - the subnet CIDR math below (a /20 per AZ out of a /16) assumes it stays in this range."
  }
}
