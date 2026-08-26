# AWS as the production/DR tier, validated against Floci first

Status: accepted

The homelab (`0002-gitops-deployment-architecture.md`) covers dev and
staging only — production was explicitly left uncreated. This ADR
establishes AWS as that production tier, running alongside the homelab
rather than replacing it: dev and staging stay on k3s, production and its
disaster-recovery counterpart move to AWS.

**Topology**: multi-AZ within each region, plus multi-region **active-passive**
— primary in `ap-southeast-3` (Jakarta, keeps data in-country), DR in
`ap-southeast-1` (Singapore, low-latency APAC pairing with full service
parity). Active-active was considered and rejected: it needs
writable-everywhere data and a conflict-resolution story, a much bigger
complexity jump than this system needs yet. See
`0005-aurora-global-database-dr-failover.md` for the failover mechanics
this topology depends on.

**Compute stays Kubernetes**: both regions run EKS, with Argo CD managing
both clusters. This preserves the existing GitOps vocabulary — Bump job,
Promotion, Sync (`CONTEXT.md`) — rather than rebuilding CI/CD on a
different compute model. ECS/Fargate and Lambda were considered and
rejected for the same reason: neither carries forward the Argo
CD/Helm/promotion pipeline already built and understood.

**Validation before spend**: the entire architecture — Terraform,
Terragrunt, EKS, Aurora Global, networking — is built and proven against
**Floci** (a local, free AWS API emulator) before any real AWS account is
provisioned. A real cutover is a deliberate later phase, not part of this
decision.

## Consequences

- `values-production.yaml` and `terraform/environments/production` now get
  created — the gap ADR 0002 explicitly left open.
- Two EKS clusters (primary + DR) to operate and keep in version/config
  lockstep, not one.
- Every AWS-specific ADR below (0005-0008) assumes this topology; changing
  the region pair or the active-passive choice later would ripple through
  all of them.
