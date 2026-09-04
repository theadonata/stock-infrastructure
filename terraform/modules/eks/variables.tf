variable "environment_name" {
  description = "Environment name (e.g. aws-production, aws-dr) - namespaces every resource in this module and its tags."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from the vpc module - combined with private_subnet_ids for the EKS cluster's vpc_config.subnet_ids (control-plane ENIs land across whatever subnets they're given, and a future ALB, ADR 0006, needs the public ones anyway)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from the vpc module - where every worker node lives; the node group uses these exclusively."
  type        = list(string)
}

# --- EKS (STOCK-7, ADR 0004 "compute stays Kubernetes") ---

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS control plane. Pinned rather than left floating - see terraform/README.md's \"Provider versions\" note on why this project pins deliberately. Bumped by hand to the latest EKS-supported version after checking release notes, not automatically."
  type        = string
  default     = "1.36"
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
