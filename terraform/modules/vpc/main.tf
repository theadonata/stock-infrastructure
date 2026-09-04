# Primary-region (and DR-region) networking - STOCK-7, ADR 0004's
# multi-AZ topology and ADR 0006's "one NAT gateway per AZ" decision.
# One instance of this module per environment (aws-production, aws-dr),
# parameterized via var.vpc_cidr / var.az_count - same shared-module-plus-
# terragrunt-inputs pattern as the homelab environments (see
# terraform/README.md). Originally lived directly in modules/aws-environment
# as vpc.tf; split into its own module per CLAUDE.md's "one module per
# infrastructure component" convention - see modules/aws-environment/main.tf
# for how this is wired in, and modules/aws-environment/moved.tf for the
# state-address migration this split needed.

# Picks az_count AZs out of whatever the region actually has. Deliberately
# not hardcoded (e.g. "ap-southeast-3a") - the two regions this module runs
# in (ap-southeast-3, ap-southeast-1) don't share AZ names, and hardcoding
# would make the module non-portable between them.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # One /20 per AZ out of the /16 VPC CIDR: public subnets take the first
  # az_count /20s, private subnets take the next az_count /20s after a gap
  # (indices 8+) so the two ranges never collide even at az_count's max (4).
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for EKS - nodes/pods resolve the API server via DNS

  tags = {
    Name        = "stock-hpp-${var.environment_name}"
    Project     = "stock-hpp"
    Environment = var.environment_name
  }
}

# Trivy AWS-0104: the default security group a VPC comes with should deny
# all traffic, not be left at its permissive default - nothing is meant to
# use it (every real resource below gets its own purpose-built SG).
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "stock-hpp-${var.environment_name}-default-sg-locked-down"
    Environment = var.environment_name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "stock-hpp-${var.environment_name}-igw"
    Environment = var.environment_name
  }
}

# Public subnets - one per AZ. Hosts each AZ's NAT gateway; also where a
# future ALB (ADR 0006) would attach once ingress is wired up.
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = local.public_subnet_cidrs[count.index]

  # Trivy AWS-0164: don't auto-assign public IPs at the subnet level. Left
  # off (the secure default) rather than suppressed - nothing here needs
  # it. NAT gateways (this file) get their own EIP regardless of this
  # setting, and a future ALB (ADR 0006) gets its own public IP the same
  # way; this only matters for a bare EC2 instance launched into the
  # subnet without an explicit public IP, and nothing does that.
  map_public_ip_on_launch = false

  tags = {
    Name                     = "stock-hpp-${var.environment_name}-public-${local.azs[count.index]}"
    Environment              = var.environment_name
    "kubernetes.io/role/elb" = "1" # tells the AWS Load Balancer Controller (ADR 0006) this subnet is ALB-eligible
  }
}

# Private subnets - one per AZ. EKS control-plane ENIs and every worker
# node live here; no route to the internet gateway, only to this AZ's own
# NAT gateway (below).
resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = local.private_subnet_cidrs[count.index]

  tags = {
    Name                              = "stock-hpp-${var.environment_name}-private-${local.azs[count.index]}"
    Environment                       = var.environment_name
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# One Elastic IP + NAT gateway per AZ (ADR 0006 - explicitly rejects a
# single shared NAT gateway: losing one AZ's NAT would otherwise take
# every other AZ's egress down with it).
resource "aws_eip" "nat" {
  count  = var.az_count
  domain = "vpc"

  tags = {
    Name        = "stock-hpp-${var.environment_name}-nat-${local.azs[count.index]}"
    Environment = var.environment_name
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "stock-hpp-${var.environment_name}-nat-${local.azs[count.index]}"
    Environment = var.environment_name
  }

  depends_on = [aws_internet_gateway.this]
}

# Single public route table, shared by all public subnets - they're
# symmetric (all route 0.0.0.0/0 to the same IGW).
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "stock-hpp-${var.environment_name}-public"
    Environment = var.environment_name
  }
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ, each pointing 0.0.0.0/0 at its own AZ's
# NAT gateway only - the point of ADR 0006's per-AZ NAT decision. A single
# shared private route table pointed at one NAT gateway would silently
# undo that isolation.
resource "aws_route_table" "private" {
  count = var.az_count

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name        = "stock-hpp-${var.environment_name}-private-${local.azs[count.index]}"
    Environment = var.environment_name
  }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
