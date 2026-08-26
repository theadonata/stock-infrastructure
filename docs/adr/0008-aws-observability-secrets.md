# AWS-native managed observability and Secrets Manager, distinct from the homelab stack

Status: accepted

**Observability**: the AWS production/DR tier uses a full AWS-native
managed stack — Amazon Managed Prometheus, Amazon Managed Grafana, and
CloudWatch Logs — rather than replicating the homelab's self-hosted
Prometheus+Grafana+Loki+Alloy+Alertmanager stack
(`0003-observability-stack.md`) into EKS. This is a genuine replacement,
not a hybrid: the two environments diverge on purpose, because AWS has
managed-service alternatives that don't exist in a homelab context — the
same reasoning ADR 0002 already applied when it chose self-managed Postgres
*specifically for* the homelab. `CONTEXT.md`'s "Monitoring stack" term has
been split accordingly into **Homelab monitoring stack** (ADR 0003's stack,
dev/staging) and **AWS observability stack** (this ADR, production/DR) to
keep the two unambiguous going forward.

CloudWatch health checks feeding Route53 are the failure detector driving
the automated DR failover in `0005-aurora-global-database-dr-failover.md`,
and are deliberately independent of anything running inside the primary
region's own cluster — the failover trigger can't depend on in-region
monitoring that goes down along with the region it's meant to detect.

**Secrets**: the AWS tier uses **AWS Secrets Manager + External Secrets
Operator**, not Sealed Secrets (ADR 0002's homelab choice — one controller
pod, no external key distribution). Secrets Manager replicates cross-region
natively, so the warm-standby app in `ap-southeast-1`
(`0004-aws-production-dr-architecture.md`) already has valid secrets
without a separate sync step. Sealed Secrets was considered and rejected
for AWS specifically because its ciphertext is bound to one controller's
key, which would complicate keeping secrets valid across two regions'
clusters.

## Consequences

- Dashboards and alerting are genuinely different between homelab and AWS
  now — no shared Grafana provisioning ConfigMaps. Debugging production
  requires AWS Managed Grafana access, not the homelab Grafana instance.
- ADR 0003's Alertmanager → Discord routing does not carry over
  automatically; an equivalent CloudWatch Alarms → Discord (or other
  channel) path needs its own decision if that notification channel should
  continue in production — not covered by this ADR.
- Two secrets-management patterns now exist across environments (Sealed
  Secrets on homelab, Secrets Manager + External Secrets Operator on AWS),
  mirroring the two-ingress-pattern consequence noted in
  `0006-aws-networking-ingress-registry.md`.
