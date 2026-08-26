# Aurora Global Database for the AWS data tier, with automated cross-region failover

Status: accepted

`0002-gitops-deployment-architecture.md` chose a self-managed, in-cluster
Postgres `StatefulSet` for the homelab specifically because "in a homelab
context there's no realistic external managed alternative." That
constraint doesn't hold on AWS, and the multi-region active-passive
topology (`0004-aws-production-dr-architecture.md`) needs a data layer with
a real cross-region replication and failover story — so the AWS data tier
uses **Aurora PostgreSQL Global Database** instead.

**Targets**: RPO ≈ seconds (Aurora Global's typical sub-second cross-region
replication lag), RTO ≈ minutes. Minutes-not-seconds was a deliberate
choice: hitting a seconds-scale RTO would require an active-active,
writable-everywhere setup (rejected in ADR 0004) — accepting a short,
bounded outage during failover is the tradeoff for keeping the DR region
read-only and the architecture simple.

**Failover is automated, not human-gated**: CloudWatch health checks
(independent of anything running inside the primary region's own cluster —
see `0008-aws-observability-secrets.md`) feed Route53, which triggers a
Lambda/Step Functions runbook that promotes the Aurora Global secondary to
a standalone writable cluster and flips DNS. This deliberately inverts
ADR 0002's human-checkpoint philosophy (staging requires a human to trigger
sync): that pattern gates routine, reversible *deployments* behind a
human; this gates an *emergency recovery* path behind automation, because
the risk in DR is being too slow, not too fast — a minutes-scale RTO isn't
achievable if it depends on an on-call human being awake and reachable.

**Considered and rejected**:
- **RDS cross-region read replica** — no clean, managed promotion path;
  Aurora Global Database is purpose-built for this failover pattern.
- **Self-managed Postgres with manual cross-region streaming replication**
  — reintroduces the operational burden AWS specifically removes the
  justification for.
- **Human-triggered failover** — undermines the minutes-scale RTO target.

## Consequences

- The DR region's database is read-only under normal operation —
  application design must not assume a writable DB is available in
  `ap-southeast-1` outside a failover event.
- Promotion is one-directional: once the secondary is promoted, restoring
  the original primary-secondary relationship (fail-back) is a separate,
  documented operation, not automatic.
- The warm-standby app tier in DR (`0004`) depends on this ADR's failover
  timing actually landing in the minutes-scale RTO — if Aurora Global's
  real promotion time is measured against Floci and it doesn't hold up,
  this ADR's target needs revisiting before real cutover.
