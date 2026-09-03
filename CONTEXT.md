# stock-infrastructure

GitOps deployment repo for the stock-hpp app — Helm chart, Terraform, and the
Argo CD promotion pipeline that moves a built image from dev to staging.

## Language

**Bump job**:
The CI job, living in `stock-backend`'s/`stock-frontend`'s own `ci.yml`, that
runs after an image is built and pushed, edits the target `values-<env>.yaml`'s
image tag field(s) via `yq`, and opens a pull request against
`stock-infrastructure`. One bump job per {app, environment} pair.
_Avoid_: deploy job, release job — it never touches the cluster directly, Argo
CD does that.

**Bump PR**:
The pull request a bump job opens. Touches exactly one `values-<env>.yaml`'s
image tag field(s), nothing else.

**Promotion**:
Moving a specific image from running in dev to running in staging. The bump
PR auto-merges (same as dev), so this happens at the git level on its own;
distinct from *sync* (below) — promotion decides *what* should run in
staging, sync is Argo CD actually making it run.
_Avoid_: deploy, release, ship.

**Promotion gate**:
Staging's one remaining human checkpoint: a human triggers the Argo CD sync
(`kubectl patch application stock-hpp-staging ...`) to actually roll out
whatever the auto-merged bump PR last set. The bump PR merging does not by
itself deploy anything to staging — only the sync does.

**Sync**:
Argo CD's term for reconciling the live cluster to match what git currently
says. Dev syncs automatically (`automated_sync = true`); staging only syncs
when a human explicitly triggers it.

**stock-backend-db image**:
The custom Postgres image (with schema/initdb baked in) built by
`stock-backend/db/Dockerfile` via `stock-backend`'s own `build-db-image`/
`push-db-image` CI jobs. Referenced in the Helm chart as `postgres.image.*`,
which reads as a vanilla third-party Postgres image but isn't — it's an
app-owned artifact that moves in lockstep with `backend.image.tag`, bumped by
the same `stock-backend` bump job in the same PR.
_Avoid_: "the postgres image" unqualified — always distinguish it from a
stock/third-party Postgres image when it matters (e.g. deciding what a bump
job is responsible for).

**Homelab monitoring stack**:
The shared Prometheus + Grafana + Loki + Alloy + Alertmanager deployment in
the `monitoring` namespace (see `0003-observability-stack.md`), synced from
one single-source Argo CD Application. One instance covers both
`stock-hpp-dev` and `stock-hpp-staging` — it is not duplicated per
environment the way the app itself is. Does not include tracing (Tempo is
deferred until an app actually emits traces).
_Avoid_: "monitoring stack" unqualified once an AWS environment exists —
say "homelab monitoring stack" to distinguish it from the **AWS
observability stack** (below). Before the AWS decision, "monitoring
stack"/"the monitoring namespace" was the unqualified project term,
matching the namespace/Application name; that's now ambiguous.

**AWS observability stack**:
The managed-service observability layer for the AWS production/DR
environment: Amazon Managed Prometheus + Amazon Managed Grafana +
CloudWatch Logs. Deliberately not the same technology as the **homelab
monitoring stack** — AWS has managed-service alternatives that don't exist
in a homelab context, so the two environments diverge here on purpose
rather than by accident. CloudWatch health checks feeding Route53 are the
automated-failover trigger (see the AWS deployment ADRs) and must stay
independent of anything running inside the primary region's own cluster.
_Avoid_: "monitoring stack" unqualified — always say "AWS observability
stack" to distinguish it from the homelab's Prometheus/Grafana/Loki stack.

**Alert severity** (homelab monitoring stack):
Two levels only: `critical` (needs action soon) and `warning` (worth
knowing, not urgent). No `info` tier — matches the "nobody's paged at 3am"
reasoning already in `charts/monitoring/values.yaml`'s retention comment.
_Avoid_: introducing a three-tier scheme (`info`/`warning`/`critical`)
without revisiting this — it was deliberately rejected as more granularity
than a single-operator setup needs.

**Resource-category routing**:
Alertmanager receivers for the homelab monitoring stack are split by
resource category (e.g. `CPU/Memory`, `Availability`, `Capacity`), not by
severity — severity (above) stays visible inside the message body only,
it's never a routing key. As of the `PodCPUUsageHigh` alert (the first,
and so far only, alert routed this way), kube-prometheus-stack's 150+
built-in default alert rules are *not* re-routed and still land on the
original flat `discord` receiver from `alertmanager-config-secret.sealed.yaml`.
_Avoid_: assuming every alert has its own category channel — most don't
yet; check that file's route tree before assuming otherwise.

**Floci**:
A local, free AWS API emulator ([github.com/floci-io/floci](https://github.com/floci-io/floci))
used to validate the entire AWS production/DR architecture — Terraform,
Terragrunt, EKS, Aurora Global — before any real, billable AWS account is
provisioned (`0004-aws-production-dr-architecture.md`). As of
`0009-aws-finops-cost-guardrails.md`, also the basis for pre-cutover cost
estimation: Terraform plans run against Floci feed Infracost to produce a
projected AWS bill before real spend exists.
_Avoid_: confusing it with a cost-management/FinOps tool itself — Floci is
an infrastructure emulator; Infracost is the cost-estimation layer built
on top of what it validates.

**FinOps guardrails**:
The visibility+alerting half of this project's AWS cost governance
(`0009-aws-finops-cost-guardrails.md`) — deliberately scoped to exclude
automated cost optimization (rightsizing, Savings Plans, auto-scaling on
budget breach; that's a later phase, not this one). Two parts: (1)
pre-cutover cost estimation via **Floci** + Infracost against Terraform
plans, and (2) post-cutover **AWS Budgets** (tag-filtered by
`environment`/`component`, reusing the existing `{app, environment}`
vocabulary — see "Bump job" above) notifying a dedicated Discord channel.
_Avoid_: assuming a budget breach triggers any automated action — it's
notify-only by deliberate choice, since DR's warm-standby topology
(`0004`/`0005`) must never be silently touched by cost-driven automation,
matching this project's human-gated-apply philosophy (`0007`).

**"Spike"**:
Not project vocabulary — avoid it. A request to alert on a resource
"spike" was deliberately implemented as a sustained-threshold alert
(value above X for Y minutes, same mechanism as kube-prometheus-stack's
own default rules), not rate-of-change/anomaly detection against a
baseline. Say "sustained-threshold alert."
