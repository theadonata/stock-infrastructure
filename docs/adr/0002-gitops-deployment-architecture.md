# GitOps deployment architecture for the stock-hpp homelab cluster

Status: accepted

Supersedes `gitops-plan.md`, `ci-plan.md`, and `infrastructure.md` (deleted
— their decision content lives here; their reference/how-to content either
lives in the code they describe, or in `runbook.md`/`README.md`).
`infrastructure.md`'s 2026-08-12 deployability assessment is what surfaced
the two app-level fixes and the tooling questions below; every open
decision it flagged was resolved here.

## Platform tooling

**k3s** as the k8s distribution: single binary, ships with Traefik ingress
+ local-path storage + ServiceLB built in — zero extra installs for a
homelab single-node box. Traefik matters later: it does weighted traffic
splitting natively, which a future canary phase needs.

**Argo CD** as the GitOps controller (not Flux or a bare CI-driven apply):
its Application CRD maps 1:1 onto "one app per environment," it has a real
UI (useful for solo-operator visibility), and Argo Rollouts — for future
progressive delivery — is the same project family, so that's an incremental
CRD+controller install later, not a swap to a different ecosystem.

**Helm** for manifests (one umbrella chart, `charts/stock-hpp`, with
per-environment values files), not raw YAML or Kustomize — the standard
Argo CD + Helm pattern. Non-obvious consequence: Argo CD renders this chart
via `helm template` only, never `helm install`/`upgrade`, so Helm's own
hook lifecycle (`helm.sh/hook`) never actually fires — Argo CD's own hook
annotations (`argocd.argoproj.io/hook`) drive ordering instead (see Fix A
below).

**Traefik** for ingress — already built into k3s, no extra install, and the
same tool later drives canary traffic splitting.

**Sealed Secrets** for secrets-in-git, not SOPS+age or Vault — one
controller pod, `kubeseal` encrypts client-side into a `SealedSecret` CR
safe to commit. Simplest option with no external key distribution to CI and
no extra service, appropriate for a single homelab cluster. Kept as plain
manifests outside the Helm chart rather than templated values, since
sealed-secret ciphertext is opaque and environment-specific — nothing to
template.

**Postgres**: in-cluster `StatefulSet` using `stock-backend`'s own
`db/Dockerfile` image (already built/pushed by its CI), templated directly
in the chart — not a third-party chart like Bitnami's `postgresql` subchart,
and not an external managed instance. In a homelab context there's no
realistic external managed alternative, and the project already ships its
own Postgres image with custom `initdb` scripts, so templating it directly
was the explicit choice rather than an assumption.

**Terraform/GitOps boundary**: Terraform manages the bootstrap layer (k3s
itself when same-machine, Argo CD, Sealed Secrets) and registers each
environment's Argo CD `Application` object — everything downstream of "Argo
CD knows this Application exists" stays pure GitOps (Helm chart + values
files + PRs), not Terraform. Terraform's own CI is validate-only (`fmt
-check` + `validate -backend=false`), never `plan`/`apply` — every
environment uses local state and the real cluster is a homelab box hosted
runners can't reach, so there's no shared state to plan against and nothing
to apply to; applying stays a human running `scripts/bootstrap-cluster.sh`.

**Image promotion**: a CI job that opens a PR against `stock-infrastructure`
and auto-merges it for both dev and staging, not Argo CD Image Updater's
default direct-branch-commit mode — the latter cuts against every
repo's hard "never push directly to main, always PR" rule, while a small CI
job reusing the existing branch→PR flow keeps it auditable and needs no
second controller running alongside Argo CD. The cross-repo write
credential this requires is its own decision — see
[0001-cross-repo-bump-credential.md](./0001-cross-repo-bump-credential.md).

**Production environment**: intentionally not created yet (no
`values-production.yaml`, no `terraform/environments/production`) — CI
doesn't emit a `:production` image tag either, so there's nothing yet to
promote there.

## Two app-level fixes this architecture required

**Fix A — migrations run as an Argo CD PreSync hook Job, not a pod-startup
command.** The compose-only pattern (`alembic upgrade head && uvicorn ...`)
would race under `replicas > 1` if copied verbatim into a Deployment. Fixed
with `charts/stock-hpp/templates/backend-migrate-job.yaml`, a `Job`
annotated `argocd.argoproj.io/hook: PreSync` (not `helm.sh/hook` — see the
Helm/Argo CD note above) that Argo CD runs to completion before every
sync's rollout.

**Fix B — the frontend's backend URL is injected at container runtime, not
baked in at `docker build` time.** Vite inlines `VITE_API_BASE_URL` into
the built JS bundle at build time, which meant one image was permanently
tied to one backend URL — incompatible with "build once, promote the same
image through dev→staging." Fixed with a placeholder build arg, an nginx
entrypoint script that runs `envsubst` to generate `/config.js` from the
container's `API_BASE_URL` env var at start, and `client.ts` reading
`window.__APP_CONFIG__?.API_BASE_URL` first with the Vite env var as
fallback (keeps `npm run dev` unchanged).

## Not yet decided

Real, currently-open gaps this architecture doesn't close — not silently
assumed, just not built yet:

- A DB-aware `/readyz` readiness probe, distinct from the DB-free
  `/healthz` liveness check — needed before a health-gated rollout can be
  fully trusted (a DB-unreachable release would still show pods "Ready"
  without it).
- Automating admin-account seeding (`scripts/seed_admin.py`) as a one-time
  Job after the migration Job, rather than a manual `kubectl exec`.
- Argo Rollouts / canary delivery with Traefik weighted traffic-splitting
  and Prometheus-driven auto-rollback — deferred by original design, not a
  re-architecture when it happens (Argo Rollouts is the same project family
  as Argo CD and renders through the same Helm/Argo CD pipeline).
