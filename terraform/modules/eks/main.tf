# EKS cluster - STOCK-7, ADR 0004 ("compute stays Kubernetes", both
# primary and DR regions run EKS) and ADR 0006 (ALB ingress / ECR, which
# builds on top of this cluster in a later ticket - not this one).
# Originally lived directly in modules/aws-environment as eks.tf (plus the
# KMS key below, which lived in that module's main.tf); split into its own
# module per CLAUDE.md's "one module per infrastructure component"
# convention - see modules/aws-environment/main.tf for how this is wired
# in, and modules/aws-environment/moved.tf for the state-address migration
# this split needed. Takes the vpc module's subnet outputs as inputs
# rather than reaching into that module's resources directly.

# Customer-managed KMS key for this environment (Trivy AWS-0132 pattern
# already established by STOCK-6: encrypt with a CMK instead of an
# AWS-managed default, for auditability/key-rotation control). Reused by
# both the cluster's secrets envelope encryption and the node group's EBS
# volumes, rather than minting a key per resource - this is a
# single-app-per-environment cluster, not a multi-tenant one where blast
# radius would argue for separating them.
resource "aws_kms_key" "this" {
  description         = "CMK for the ${var.environment_name} environment (EKS secrets + node EBS encryption)"
  enable_key_rotation = true
}

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "stock-hpp-${var.environment_name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = "stock-hpp-${var.environment_name}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    # Both public and private subnets: EKS places cross-AZ ENIs for the
    # control plane across whatever subnets it's given, and a future ALB
    # (ADR 0006) needs the public ones anyway.
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_private_access = true # always on: in-VPC access (nodes, a future bastion) must never depend on the public toggle below
    endpoint_public_access  = var.eks_endpoint_public_access
    public_access_cidrs     = var.eks_endpoint_public_access ? var.eks_public_access_cidrs : ["127.0.0.1/32"] # Trivy AWS-0039 flags 0.0.0.0/0 even when public access is off; this is inert but keeps the field's default off the scanner's radar
  }

  # Trivy AWS-0040: encrypt Kubernetes Secrets at the etcd layer with a
  # customer-managed key, not just the AWS-managed default.
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.this.arn
    }
  }

  # Trivy AWS-0038: all five control-plane log types, not just some -
  # cheap in an emulated environment, and this is the one place a real
  # cutover would want full audit/authenticator logs from day one anyway.
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name        = "stock-hpp-${var.environment_name}"
    Environment = var.environment_name
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "stock-hpp-${var.environment_name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json
}

# The three managed policies every EKS worker node needs: node bootstrap
# permissions, the CNI plugin's ENI/IP management, and read-only ECR pulls
# (GHCR-primary today, but ADR 0006's ECR mirror needs this regardless of
# which registry actually gets pulled from).
resource "aws_iam_role_policy_attachment" "eks_node_worker_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Launch template purely for the hardening EKS's own node-group defaults
# don't cover (IMDSv2, encrypted root volume) - deliberately no image_id:
# leaving it unset lets EKS fill in its own recommended AMI for the node
# group's own ami_type (below), so this never drifts against a hand-picked
# AMI ID going stale.
resource "aws_launch_template" "eks_node" {
  name_prefix = "stock-hpp-${var.environment_name}-eks-node-"

  # Trivy AWS-0130: require IMDSv2 (token-based), not the v1 default that
  # lets any process on the box read instance metadata unauthenticated.
  # hop_limit 2 (not the default 1) so pods routed through the CNI's
  # ENI hop can still reach IMDS for the CNI/CSI drivers that need it.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # Trivy AWS-0131: encrypt the root EBS volume with the same
  # environment-scoped CMK used for EKS secrets above, instead of leaving
  # it unencrypted.
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.eks_node_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.this.arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "stock-hpp-${var.environment_name}-eks-node"
      Environment = var.environment_name
    }
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "stock-hpp-${var.environment_name}"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids # workers stay private - only the NAT path (vpc module) gets them outbound
  instance_types  = var.eks_node_instance_types
  # Required whenever the launch template above doesn't specify an AMI
  # itself (it doesn't, on purpose - see that resource's comment) - tells
  # EKS which of its own recommended AMIs to fill in.
  ami_type = "AL2023_x86_64_STANDARD"

  launch_template {
    id      = aws_launch_template.eks_node.id
    version = aws_launch_template.eks_node.latest_version
  }

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Environment = var.environment_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker_policy,
    aws_iam_role_policy_attachment.eks_node_cni_policy,
    aws_iam_role_policy_attachment.eks_node_ecr_readonly,
  ]

  # Node group's own scaling_config.desired_size drifts once anything
  # (cluster-autoscaler, a manual scale event) changes live capacity -
  # not tracked here since none of that exists yet, but ignoring desired
  # size on future re-applies is the standard EKS-managed-node-group
  # pattern once it does. Left commented rather than enabled now, since
  # enabling it today (before autoscaling exists) would silently swallow
  # a genuine terragrunt-input change to eks_node_desired_size instead.
  # lifecycle {
  #   ignore_changes = [scaling_config[0].desired_size]
  # }
}
