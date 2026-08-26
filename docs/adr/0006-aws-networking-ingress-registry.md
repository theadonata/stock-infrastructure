# AWS Load Balancer Controller and ECR, replacing Traefik ingress for the AWS tier

Status: accepted

**Ingress**: EKS uses the **AWS Load Balancer Controller**, driving native
ALB/NLB resources from Kubernetes Ingress/Gateway objects — not Traefik, as
the homelab uses (`0002-gitops-deployment-architecture.md`). This is a
deliberate divergence: ADR 0002 chose Traefik partly because k3s ships it
for free, and specifically flagged its native weighted traffic-splitting as
what a future canary phase would need. That canary/progressive-delivery
plan (still "not yet decided" per ADR 0002) will need to target ALB
traffic-shifting instead — most likely via Argo Rollouts' ALB integration,
since Argo Rollouts itself still applies (same project family as Argo CD,
per ADR 0002) — when it's designed for AWS.

**Registry**: CI keeps building and pushing images to GHCR unchanged, then
mirrors into **ECR** with cross-region replication enabled between
`ap-southeast-3` and `ap-southeast-1`. Both EKS clusters — including the
warm-standby DR cluster (`0004`) — always have a private, VPC-local image
copy this way, without image pulls depending on GitHub's availability or
public internet egress during exactly the kind of regional incident DR
exists to survive. GHCR-only (no ECR mirror) was considered and rejected
for that reason.

**NAT gateways**: one per Availability Zone in each region's VPC, not a
single shared NAT gateway. A shared NAT gateway was considered and
rejected: it would make the multi-AZ resilience target
(`0004-aws-production-dr-architecture.md`) partly fictional — pods could
still schedule across AZs, but if the NAT gateway's AZ went down, every
other AZ would still lose outbound internet (image pulls, external APIs)
along with it.

## Consequences

- Two ingress technologies now exist across environments — Traefik on the
  homelab, ALB on AWS — rather than one shared pattern.
- ECR cross-region replication adds a small ongoing storage/transfer cost
  per image, proportional to image size and push frequency.
- One NAT gateway per AZ per region is the standard (not the
  cheapest-possible) networking cost of the multi-AZ decision in ADR 0004
  — a deliberate tradeoff, not an oversight.
