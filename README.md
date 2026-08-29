# stock-infrastructure

CI/CD, deployment, and IaC for the Stock/HPP business-finance project.

Part of the `stock-*` multi-repo project. See CLAUDE.md for scope and
sibling-repo relationships.

## Purpose

This repo owns CI/CD and deployment for the project: a homelab Kubernetes
(k3s) cluster, deployed and kept in sync via GitOps (Argo CD + a Helm
chart), provisioned with Terraform. It wires together the
independently-built `stock-backend` and `stock-frontend` container images
by referencing them by tag — it does not read or depend on either repo's
source directly.

## Current status

The platform choice is made and built: **k3s** (k8s distro) + **Argo CD**
(GitOps controller) + **Helm** (chart packaging) + **Terraform**
(provisions k3s itself, Argo CD, Sealed Secrets, and the per-environment
Argo CD Applications) + **Sealed Secrets** (encrypted secrets in git). See
`docs/adr/0002-gitops-deployment-architecture.md` for the full design and
why these were chosen.

Built and working: the Helm chart (`charts/stock-hpp/`), the full Terraform
layer (`terraform/`), and a step-by-step runbook (`runbook.md`) with a
wrapper script (`scripts/bootstrap-cluster.sh`) to drive it. Both `dev` and
`staging` environments are wired up (dev auto-syncs, staging requires a
manual sync — see `runbook.md` §1–3).

Also built: a shared Prometheus/Grafana/Loki/Alloy/Alertmanager monitoring
stack (`charts/monitoring/`), one instance covering both `dev` and
`staging` — see `docs/adr/0003-observability-stack.md` and `runbook.md`
§10.

The `bump-dev`/`bump-staging` CI jobs that automate image promotion exist in
`stock-backend`'s/`stock-frontend`'s `.github/workflows/ci.yml` and are set
up and verified working end-to-end (both environments' bump PRs auto-merge;
see `runbook.md` §0 "Enabling automatic image promotion" for the one-time
GitHub account/repo setup this depends on, if reproducing this elsewhere).
The manual PR flow in `runbook.md` §2 remains as a fallback if those jobs
are ever broken or that setup hasn't been done.

`stock-backend` and `stock-frontend` each still own their own `Dockerfile`
and `docker-compose.yml` for local development, independent of this repo —
this repo builds on top of those images rather than replacing them.

## Component reference

For learning/orientation: what each piece actually is and why it's there.
This is a map, not the full rationale — `docs/adr/` has the "why" in depth
for anything that says "see the ADR" below.

### `charts/stock-hpp/` — the application itself

One Helm chart, rendered once per environment (`values.yaml` defaults +
`values-<env>.yaml` overrides — image tags, ingress host, CORS origin,
runtime API base URL):

- **`backend/deployment.yaml` + `service.yaml` + `configmap.yaml`** — the
  FastAPI app. The ConfigMap holds only non-secret env vars (JWT algorithm,
  token expiry, CORS origin); `DATABASE_URL`/`JWT_SECRET` come from the
  SealedSecret named in `.Values.secretName` instead.
- **`backend/migrate-job.yaml`** — a one-shot `Job`, not part of the
  Deployment's own startup command. Runs `alembic upgrade head` then
  `scripts.seed_admin` (idempotent, safe to re-run every sync) *before* the
  backend rolls out, via Argo CD's `PreSync` hook annotation — not
  `helm.sh/hook`, since Argo CD only ever `helm template`s this chart and
  never actually runs Helm's own install/upgrade hook lifecycle. This is
  "Fix A" in `docs/adr/0002-gitops-deployment-architecture.md`: it exists
  because running migrations at pod startup (fine for a single local
  `docker compose` container) would race under multiple replicas.
- **`frontend/deployment.yaml` + `service.yaml` + `configmap.yaml`** —
  nginx serving the built React SPA. The ConfigMap carries
  `apiBaseUrl`, injected into the container at *runtime* (an nginx
  entrypoint script + `window.__APP_CONFIG__`), not baked into the image at
  `docker build` time — "Fix B" in the same ADR, needed so one built image
  can be promoted dev→staging without a rebuild per environment.
- **`postgres/statefulset.yaml` + `pvc.yaml` + `service.yaml`** — Postgres,
  using `stock-backend`'s own custom image (with its `initdb` scripts), not
  a third-party chart — this project already owns that image, so there's
  nothing a generic Postgres chart would add.
- **`ingress.yaml`** — one Traefik `Ingress` (k3s' built-in ingress
  controller) per environment: `/api` routes to the backend Service,
  everything else to the frontend (which handles its own client-side
  routing).

### `charts/monitoring/` — shared observability stack

A *separate* chart, one instance shared by both `dev` and `staging` (not
duplicated per environment — see `docs/adr/0003-observability-stack.md`).
Unlike Postgres above, these are genuinely third-party infra with no
app-specific logic, so they're pulled in as Helm chart **dependencies**
(`Chart.yaml`) rather than hand-written manifests:

- **`kube-prometheus-stack`** (one upstream chart, three tools):
  **Prometheus** scrapes and stores metrics (15-day retention on a PVC);
  **Grafana** is the dashboard/UI, reachable at `grafana.dev.lan` via its
  own Traefik Ingress, with dashboards provisioned from ConfigMaps
  (committed to this repo) rather than clicked together by hand, so they
  survive even if Grafana's own PVC is ever lost; **Alertmanager** routes
  firing alerts to a Discord channel via a webhook.
- **`loki`** — log storage/query backend, running in `SingleBinary` mode
  with plain filesystem storage (no object-storage service exists in this
  homelab, same reasoning as Postgres above).
- **`alloy`** — the log-shipping agent (DaemonSet, one per node): tails
  every pod's stdout/stderr on its node and forwards it to Loki, labelled
  by namespace/pod/container so Grafana's Loki datasource can filter the
  same way `kubectl logs` does.
- **`templates/*-secret.sealed.yaml`** — Grafana's admin login and
  Alertmanager's Discord webhook config, as `SealedSecret`s (see
  `charts/monitoring/README.md` for how to regenerate them).

Together: Prometheus+Grafana answer "what are my metrics," Loki+Alloy
answer "what did my pods log," Alertmanager answers "who do I tell when
something's wrong."

### `terraform/` — provisions everything *up to* GitOps, no further

Terragrunt-orchestrated (see `terraform/README.md` for the full layout and
command reference). The boundary that matters: Terraform's job stops at "an
Argo CD `Application` exists and knows where to sync from" — everything
downstream of that (what actually runs in the cluster) is pure GitOps via
the two charts above, not further `terraform apply` runs.

- **`modules/k3s`** — installs k3s itself via a `local-exec` provisioner
  (there's no official k3s Terraform provider); only relevant if the
  cluster runs on the same machine you're running Terraform from.
- **`modules/argocd`** / **`modules/sealed-secrets`** — install those two
  controllers via `helm_release`.
- **`modules/namespace`** / **`modules/argocd-application`** — generic,
  reusable building blocks (a k8s namespace; an Argo CD `Application` CR,
  either multi-source or single-source depending on whether a
  `secrets_path` is given).
- **`modules/{k3s,bootstrap,app}-environment`** — thin per-phase root
  modules that wrap the building blocks above; these are what Terragrunt
  actually points at.
- **`environments/{k3s,bootstrap,dev,staging,monitoring}`** — the 5 real
  phases, applied in that dependency order. Each is just a `terragrunt.hcl`
  (no committed `.tf` files of its own) supplying that environment's own
  `inputs` to the matching module above.

### `secrets/` and `.env.local` — secrets safely in git

- **`secrets/{dev,staging}/backend-secrets.sealed.yaml`** — the backend's
  DB credentials and JWT signing secret, one `SealedSecret` per
  environment, generated by `scripts/generate-secrets.sh`.
- **`charts/monitoring/templates/*.sealed.yaml`** — Grafana/Alertmanager's
  secrets (see above), generated by `scripts/generate-monitoring-secrets.sh`.
- **`.env.local`** — the actual plaintext values those two scripts read
  from to build the ciphertext above. Gitignored, never committed; the
  `SealedSecret` files it produces *are* safe to commit, since only the
  in-cluster Sealed Secrets controller's private key can decrypt them.

### `docs/adr/` — why, not just what

- **0001** — the cross-repo credential the `bump-dev`/`bump-staging` CI
  jobs use to open PRs against this repo from `stock-backend`/`stock-frontend`.
- **0002** — **start here**: the central architecture decision record
  (platform tooling choices, the two app-level fixes, what's deliberately
  not built yet).
- **0003** — the observability stack described above.
- **0004–0008** — a *proposed* AWS production/DR architecture (production
  Kubernetes, Aurora global database failover, networking/ingress/registry,
  CI/CD, observability/secrets) — design documents only, not yet built in
  this repo. Everything described above (the homelab k3s cluster) is what's
  actually running today.

## Design reference

See `stock-business-analyst/docs/superpowers/specs/2026-08-12-stack-architecture-design.md`
for the full stack/architecture design, including the intended
infrastructure approach.

See `docs/adr/0002-gitops-deployment-architecture.md` for the full
architecture decision record — it supersedes the original Kubernetes
deployability/scalability assessment and design plan (both since deleted;
their decisions are distilled into that ADR). Covers what was already
k8s-ready, the concrete blockers that were flagged (migration execution,
missing readiness probe, frontend's build-time backend URL — the first two
are now addressed architecturally by the Helm chart's Fix A/B, though Fix
B still needs the corresponding code change landed in `stock-frontend`
itself before it's fixed end to end), and how the open platform decisions
(k8s distribution, Postgres hosting) were resolved (k3s; in-cluster
Postgres StatefulSet).

## Operating this repo

- `runbook.md` — beginner-friendly, step-by-step operational procedures:
  first-time bootstrap, deploying a change, promoting dev → staging,
  rollback, secret rotation, troubleshooting, and disaster-recovery gaps.
  **Start here** — both for first-time setup and day-to-day use.
- `scripts/bootstrap-cluster.sh` — wrapper script that runs the first-time
  bootstrap's `terragrunt apply` steps in order (`k3s` → `bootstrap` →
  `dev` → `staging`) instead of doing each one by hand; see `runbook.md`
  §1. Supports `--plan-only` for a dry run.
- `scripts/destroy-cluster.sh` — the reverse: `terragrunt destroy` in order
  (`staging` → `dev` → `bootstrap` → `k3s`), with a "type DESTROY to
  confirm" gate. `--keep-k3s` tears down just the app layer (useful for
  re-testing bootstrap without reinstalling k3s); `--plan-only` previews
  with no changes.
- `scripts/generate-secrets.sh {dev,staging}` — builds
  `secrets/<env>/backend-secrets.sealed.yaml` from real values in
  `.env.local`, run automatically by `bootstrap-cluster.sh` for whichever
  environment doesn't already have one.
- `scripts/generate-monitoring-secrets.sh` — the same idea for the
  monitoring stack's two SealedSecrets (Grafana admin login, Alertmanager's
  Discord webhook config); see `charts/monitoring/README.md`.
- `docs/adr/` — architecture decision records: tool choices and why
  (`0002-gitops-deployment-architecture.md`), the cross-repo bump
  credential (`0001-cross-repo-bump-credential.md`), the monitoring stack
  (`0003-observability-stack.md`).
- `terraform/` — Terraform modules/environments that provision k3s itself,
  Argo CD, Sealed Secrets, namespaces, and the per-environment Argo CD
  Applications.
- `charts/stock-hpp/` — the umbrella Helm chart Argo CD renders and syncs.
- `charts/monitoring/` — the shared Prometheus/Grafana/Loki/Alloy/
  Alertmanager umbrella chart, one instance covering both `dev` and
  `staging`.
- `secrets/` — per-environment `SealedSecret` manifests (encrypted, safe to
  commit); see `secrets/dev/README.md` for how to generate them.
