# Root module for environments/{aws-production,aws-dr} - wires together the
# vpc and eks modules, one instance of each per environment. Networking and
# EKS resources themselves used to live directly in this module as vpc.tf/
# eks.tf (STOCK-7); split into ../vpc and ../eks per CLAUDE.md's "one module
# per infrastructure component" convention, so each component stays
# independently readable/testable instead of accumulating into one ever-
# growing environment module. See moved.tf for the state-address migration
# that split needed - every resource here kept its exact same address
# suffix, just nested one level deeper under module.vpc/module.eks, so
# `terragrunt plan` shows zero diff against already-applied state.
module "vpc" {
  source = "../vpc"

  environment_name = var.environment_name
  vpc_cidr         = var.vpc_cidr
  az_count         = var.az_count
}

module "eks" {
  source = "../eks"

  environment_name   = var.environment_name
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  eks_cluster_version        = var.eks_cluster_version
  eks_endpoint_public_access = var.eks_endpoint_public_access
  eks_public_access_cidrs    = var.eks_public_access_cidrs
  eks_node_instance_types    = var.eks_node_instance_types
  eks_node_desired_size      = var.eks_node_desired_size
  eks_node_min_size          = var.eks_node_min_size
  eks_node_max_size          = var.eks_node_max_size
  eks_node_volume_size_gb    = var.eks_node_volume_size_gb
}
