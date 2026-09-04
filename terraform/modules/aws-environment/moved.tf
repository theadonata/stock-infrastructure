# State-address migration for the vpc.tf/eks.tf -> ../vpc, ../eks module
# split (see main.tf's comment). Every resource kept its exact same type
# and local name, just nested one level deeper under module.vpc/module.eks
# - so each `moved` block below is a pure rename, not a
# destroy-and-recreate, and `terragrunt plan` against any already-applied
# aws-production/aws-dr state shows zero diff. Safe to run even against an
# environment that's never been applied - a `moved` block with nothing at
# its `from` address is a no-op.

moved {
  from = data.aws_availability_zones.available
  to   = module.vpc.data.aws_availability_zones.available
}

moved {
  from = aws_vpc.this
  to   = module.vpc.aws_vpc.this
}

moved {
  from = aws_default_security_group.this
  to   = module.vpc.aws_default_security_group.this
}

moved {
  from = aws_internet_gateway.this
  to   = module.vpc.aws_internet_gateway.this
}

moved {
  from = aws_subnet.public
  to   = module.vpc.aws_subnet.public
}

moved {
  from = aws_subnet.private
  to   = module.vpc.aws_subnet.private
}

moved {
  from = aws_eip.nat
  to   = module.vpc.aws_eip.nat
}

moved {
  from = aws_nat_gateway.this
  to   = module.vpc.aws_nat_gateway.this
}

moved {
  from = aws_route_table.public
  to   = module.vpc.aws_route_table.public
}

moved {
  from = aws_route_table.private
  to   = module.vpc.aws_route_table.private
}

moved {
  from = aws_route_table_association.public
  to   = module.vpc.aws_route_table_association.public
}

moved {
  from = aws_route_table_association.private
  to   = module.vpc.aws_route_table_association.private
}

moved {
  from = aws_kms_key.this
  to   = module.eks.aws_kms_key.this
}

moved {
  from = data.aws_iam_policy_document.eks_cluster_assume_role
  to   = module.eks.data.aws_iam_policy_document.eks_cluster_assume_role
}

moved {
  from = aws_iam_role.eks_cluster
  to   = module.eks.aws_iam_role.eks_cluster
}

moved {
  from = aws_iam_role_policy_attachment.eks_cluster_policy
  to   = module.eks.aws_iam_role_policy_attachment.eks_cluster_policy
}

moved {
  from = aws_eks_cluster.this
  to   = module.eks.aws_eks_cluster.this
}

moved {
  from = data.aws_iam_policy_document.eks_node_assume_role
  to   = module.eks.data.aws_iam_policy_document.eks_node_assume_role
}

moved {
  from = aws_iam_role.eks_node
  to   = module.eks.aws_iam_role.eks_node
}

moved {
  from = aws_iam_role_policy_attachment.eks_node_worker_policy
  to   = module.eks.aws_iam_role_policy_attachment.eks_node_worker_policy
}

moved {
  from = aws_iam_role_policy_attachment.eks_node_cni_policy
  to   = module.eks.aws_iam_role_policy_attachment.eks_node_cni_policy
}

moved {
  from = aws_iam_role_policy_attachment.eks_node_ecr_readonly
  to   = module.eks.aws_iam_role_policy_attachment.eks_node_ecr_readonly
}

moved {
  from = aws_launch_template.eks_node
  to   = module.eks.aws_launch_template.eks_node
}

moved {
  from = aws_eks_node_group.this
  to   = module.eks.aws_eks_node_group.this
}
