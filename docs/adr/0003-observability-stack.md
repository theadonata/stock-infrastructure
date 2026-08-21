# Observability stack as a single-source Helm-dependency chart

Status: accepted

We're adding Prometheus, Grafana, Loki, and Alloy (log shipping) for
general dev/staging visibility, plus Alertmanager with a Discord channel —
Tempo is deferred until the apps actually emit traces (neither
`stock-backend` nor `stock-frontend` has any tracing instrumentation yet).
This is broader than `0002-gitops-deployment-architecture.md`'s "Not yet
decided" section anticipated, which only mentioned Prometheus narrowly, as
input to a future Argo Rollouts canary auto-rollback — that's still an open
possibility later, not what this covers.

Unlike Postgres (hand-rolled specifically to avoid a black box around
app-owned schema/initdb), these four are genuinely third-party infra with
no app-specific customization needed, so we're pulling in upstream charts
(`kube-prometheus-stack`, `grafana/loki`, `grafana/alloy`) as Helm chart
dependencies in one new `charts/monitoring/` chart, synced as a
**single-source** Argo CD Application in a shared `monitoring` namespace —
one instance covering both `stock-hpp-dev` and `stock-hpp-staging`, not
duplicated per environment.

Single-source is deliberate, not the default choice: today's SealedSecret
incident (`stock-infrastructure` PR #23, reverted by #24) showed that plain
`sync-wave` doesn't reliably order resources *across* an Application's
multiple sources — the fix there was restoring a PreSync hook, not fixing
the ordering. Keeping this stack in one source sidesteps that failure mode
entirely rather than risking it again elsewhere. Its PVCs (Prometheus's
TSDB, Loki's chunks, Grafana's dashboard DB) must never be marked as
PreSync hooks, per the same day's `postgres-pvc.yaml`/
`postgres-statefulset.yaml`/`postgres-service.yaml` fix — plain sync-wave
is sufficient here since everything in this chart is single-source.

Grafana dashboards are provisioned via ConfigMaps (committed to this repo),
not built by hand in the Grafana UI, so they survive even if Grafana's own
PVC is ever lost or recreated — the exact failure mode the day's PVC bug
produced.

## Consequences

- Upgrading any one tool means bumping a chart dependency version, not
  hand-maintaining its CRDs/RBAC/manifests — less control, less ongoing
  maintenance burden than the Postgres pattern.
- Grafana is reachable at `grafana.dev.lan` via a Traefik Ingress,
  protected only by Grafana's own login (admin password via a SealedSecret,
  same pattern as `backend-secrets`) — no additional auth layer, acceptable
  because this cluster isn't internet-reachable, the same trust boundary
  the app itself already relies on.
- Alertmanager's Discord webhook URL is stored as a SealedSecret, same
  pattern as `backend-secrets`.
