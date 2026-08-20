# GitOps + Progressive Delivery for the Stock/HPP Homelab Cluster

## Context

The `stock-*` project (5 independent repos: backend, frontend, infrastructure,
qa, business-analyst) already has working CI in `stock-backend` and
`stock-frontend` — lint/test, SonarCloud, Trivy scanning, and (as of today)
a verified-working `docker push` of `:<sha>`, `:dev`, `:staging` tags to
`ghcr.io`. **Nothing consumes those images after the push.** `stock-infrastructure`
is the repo meant to own deployment, but per its own `CLAUDE.md`/`infrastructure.md`,
it is docs-only today: "self-hosted Kubernetes on a VPS" is the stated intent,
but no cloud provider, IaC tool, CI/CD platform, or k8s distro has been chosen,
and several deployment-readiness blockers (migration-at-startup, no runtime
frontend config, Postgres hosting) are explicitly left open.

The user wants to close this gap with **automated GitOps + progressive
delivery**, using only free/OSS tools, for a **local/homelab** deployment
target, with manifests packaged as a **Helm chart** deployed via **Argo CD**
(explicit requirement). They've confirmed:
- A lightweight k8s distro (e.g. k3s) is acceptable — unlocks the standard
  free GitOps/progressive-delivery ecosystem instead of a docker-compose-only
  approach with no mature tooling for canary analysis.
- Start **minimal**: automated GitOps deploys with simple health-check-gated
  rollout. Explicit metrics-based canary analysis is deferred, but the design
  must not require re-architecting to add it later.

This plan selects the specific tools, the two prerequisite app-level fixes
this exposes, the `stock-infrastructure` repo layout, and a phased rollout —
so the user (or a future session) can scaffold it directly.

## Tool selection

| Concern | Choice | Why |
|---|---|---|
| k8s distro | **k3s** | Single binary, ships with Traefik ingress + local-path storage + ServiceLB built in — zero extra installs for a homelab single-node box. Traefik matters later: it does weighted traffic splitting natively, which Phase 3 (canary) needs. |
| GitOps controller | **Argo CD** | Free/OSS; Application CRD maps 1:1 onto "one app per env"; has a real UI (useful for solo-operator visibility). Critically, **Argo Rollouts is the same project family**, so adding real progressive delivery later is an incremental CRD+controller install, not a swap to a different ecosystem. |
| Manifests | **Helm chart** (single umbrella chart, per-env values files) | Argo CD renders Helm charts natively via `helm template` — it does **not** run `helm install`/`upgrade`, so Helm's own hook lifecycle (`helm.sh/hook`) is never actually executed by Argo CD; Argo CD's own hook annotations drive ordering instead (see Fix A). One `charts/stock-hpp` chart with `values.yaml` defaults plus `values-dev.yaml`/`values-staging.yaml` overrides is the standard Argo CD + Helm GitOps pattern: same chart, different values per environment. |
| Ingress | **Traefik** (k3s built-in) | No extra install; same tool later drives canary traffic splitting. |
| Secrets in git | **Sealed Secrets** | One controller pod, `kubeseal` encrypts a Secret client-side into a `SealedSecret` CR safe to commit. Simpler than SOPS+age (no external key distribution to CI) or Vault (no extra service) for a single homelab cluster. Kept as plain manifests outside the Helm chart (see layout) rather than templated Helm values, since sealed-secret ciphertext is opaque and environment-specific — nothing to template. |
| Image promotion | **CI job that opens a PR against `stock-infrastructure`**, auto-merged for `dev`, human-merged for `staging` | Argo CD Image Updater's default mode commits directly to a branch, which cuts against every repo's hard "never push directly to main, always PR" rule. A small CI job doing the existing branch→PR flow the repos already use (same shape as the `ghcr` push-fix PRs done earlier this session) keeps it auditable and needs no second controller running alongside Argo CD. With Helm, the job edits `values-<env>.yaml`'s `backend.image.tag`/`frontend.image.tag` fields (via `yq eval -i`) instead of Kustomize's `images:` transformer. |
| Postgres | **In-cluster StatefulSet using `stock-backend`'s own `db/Dockerfile` image** (already built/pushed by CI), templated inside the same Helm chart | Flagged open upstream in `infrastructure.md`; in a homelab context there's no realistic external managed alternative, so this is the recommendation to make explicit rather than assume silently. A third-party chart (e.g. Bitnami's `postgresql`) doesn't fit — this project already ships its own Postgres image with custom `initdb` scripts, so it's templated directly rather than pulled in as a subchart. |

## Two prerequisite fixes this setup exposes

**A. Migrations must not run at pod startup.**
`stock-backend/Dockerfile`'s `CMD` (line 61) is already clean — plain
`uvicorn`, no migration. The `alembic upgrade head && uvicorn ...` chain only
exists in `docker-compose.yml`'s `command:` override (lines 48–49) for local
dev, and should stay there untouched. For k8s: add
`stock-infrastructure/charts/stock-hpp/templates/backend-migrate-job.yaml`, a
`Job` using the same image as the Deployment, command overridden to
`alembic upgrade head` only, annotated with **Argo CD's** PreSync hook
(`argocd.argoproj.io/hook: PreSync`, `hook-delete-policy: BeforeHookCreation`)
— **not** `helm.sh/hook`, since Argo CD only runs `helm template` on this
chart and applies the output itself; Helm's own hook lifecycle never fires.
Argo CD then runs the Job to completion before every sync's rolling update —
removing the race that copying the compose command verbatim into a Deployment
would introduce under multiple replicas or a future canary rollout.

**B. Frontend must stop baking the backend URL in at build time.**
`stock-frontend/src/api/client.ts:6` reads
`import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8000"` — a real
per-environment URL baked in at `docker build` time defeats "build once,
promote the same image through dev→staging." Fix:
- Build with a placeholder (`ARG VITE_API_BASE_URL=__RUNTIME_API_BASE_URL__`)
  instead of a real URL, so the same `:<sha>` image is what promotes.
- Add `stock-frontend/public/config.js.template` (one line:
  `window.__APP_CONFIG__ = { API_BASE_URL: "${API_BASE_URL}" };`) and one
  `<script src="/config.js">` tag in `index.html`, loaded before the app bundle.
- Add `stock-frontend/docker-entrypoint.sh`, copied into the image's
  `/docker-entrypoint.d/40-inject-config.sh` (nginx's stock image auto-runs
  scripts there on container start) — runs `envsubst` to generate
  `/usr/share/nginx/html/config.js` from the container's `API_BASE_URL` env var.
- `client.ts:6` becomes: read `window.__APP_CONFIG__?.API_BASE_URL` first,
  fall back to `import.meta.env.VITE_API_BASE_URL` — keeps `npm run dev`
  behavior unchanged (no `config.js` exists there).
- Per-environment value supplied via `frontend.config.apiBaseUrl` in
  `values-dev.yaml`/`values-staging.yaml`, rendered into a `ConfigMap` by
  `charts/stock-hpp/templates/frontend-configmap.yaml` and mounted as the
  container's `API_BASE_URL` env var.

**Recommended companion (not required to build GitOps, but worth doing
alongside):** `app/main.py`'s `/healthz` (line 30) deliberately skips the DB
(`"""...deliberately does not touch the DB..."""`). Since Phase 1/2 rely on
"pods became Ready" as the health signal Argo CD trusts, a DB-unreachable
release would still show "Healthy" without a DB-aware `/readyz` + matching
k8s readiness probe. Worth adding before relying on health-gated rollouts in
anger.

## `stock-infrastructure` repository layout

**Update:** the bootstrap layer and the per-environment Argo CD
`Application` objects are now Terraform-managed (`terraform/`) instead of
the hand-applied `kubectl apply -f`/hand-written YAML originally sketched
here — see `terraform/README.md` for the full rationale. Even k3s itself is
now Terraform-managed (`terraform/environments/k3s`) when the cluster runs
on the same machine as Terraform; `bootstrap/k3s-install.md` is kept only
for the separate-box case. `argocd-install.yaml` and
`sealed-secrets-install.yaml` are superseded by
`terraform/modules/argocd` and `terraform/modules/sealed-secrets`.
`argocd-apps/dev-app.yaml`/`staging-app.yaml` are superseded by
`terraform/modules/argocd-application`, applied via
`terraform/environments/dev` and `terraform/environments/staging`. The
Helm chart, its values files, and the `secrets/` directories are unchanged
from the original design — Terraform's job stops at "Argo CD knows this
Application exists"; everything downstream of that commit is still GitOps,
not Terraform.

```
stock-infrastructure/
├── bootstrap/
│   └── k3s-install.md                # manual, one-time — the one piece
│                                      # Terraform doesn't manage, see terraform/README.md
├── charts/
│   └── stock-hpp/                    # umbrella Helm chart for the whole stack
│       ├── Chart.yaml
│       ├── values.yaml               # shared defaults: resource limits, probe
│       │                             # paths, service ports, replica counts
│       ├── values-dev.yaml           # dev overrides: image tags, apiBaseUrl, host
│       ├── values-staging.yaml       # staging overrides
│       └── templates/
│           ├── _helpers.tpl
│           ├── backend-deployment.yaml
│           ├── backend-service.yaml
│           ├── backend-migrate-job.yaml   # Argo CD PreSync hook, Fix A
│           ├── backend-configmap.yaml
│           ├── frontend-deployment.yaml
│           ├── frontend-service.yaml
│           ├── frontend-configmap.yaml    # runtime API_BASE_URL, Fix B
│           ├── postgres-statefulset.yaml
│           ├── postgres-service.yaml
│           ├── postgres-pvc.yaml
│           └── ingress.yaml               # Traefik, host-based routing
├── secrets/
│   ├── dev/backend-secrets.sealed.yaml       # SealedSecret: POSTGRES_*, DATABASE_URL, JWT_SECRET
│   └── staging/backend-secrets.sealed.yaml
├── terraform/
│   ├── modules/
│   │   ├── k3s/                        # installs k3s on the local machine (local-exec)
│   │   ├── namespace/                # generic kubernetes_namespace, reused by dev/staging
│   │   ├── argocd/                    # installs Argo CD (helm_release)
│   │   ├── sealed-secrets/             # installs the Sealed Secrets controller (helm_release)
│   │   └── argocd-application/         # generic multi-source Argo CD Application CR
│   └── environments/
│       ├── k3s/                # Phase -1 — installs k3s, applied once, before bootstrap
│       │                       # (same-machine case only; see terraform/README.md §0)
│       ├── bootstrap/        # Phase 0 — Argo CD + Sealed Secrets install, applied once
│       ├── dev/               # Phase 1 — namespace + automated-sync Application
│       └── staging/           # Phase 2 — namespace + manual-sync Application
└── .gitignore               # shared baseline unchanged; repo-specific Terraform
                              # entries (.terraform/, *.tfstate, terraform.tfvars) below it
```

`production` overlay/values file is intentionally not created yet — CI
doesn't emit a `:production` tag either. Adding it later is a copy of
`values-staging.yaml`, a copy of `terraform/environments/staging/` as
`terraform/environments/production/`, plus a `secrets/production/`.

## Phased rollout

**Phase 0 — cluster bootstrap (manual, one-time)**
1. Install k3s — `terraform/environments/k3s` if the cluster runs on the
   same machine as Terraform (see `terraform/README.md` §0), otherwise
   `bootstrap/k3s-install.md` by hand on the separate box.
2. `cd terraform/environments/bootstrap && terraform init && terraform apply`
   for Argo CD + Sealed Secrets controller (see `terraform/README.md`).
3. Sealed Secrets controller generates its keypair on first run — back up the
   private key material outside the cluster.
4. `kubeseal` `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB`/`DATABASE_URL`/`JWT_SECRET`
   for dev and staging into `secrets/{dev,staging}/backend-secrets.sealed.yaml`
   (see `secrets/dev/README.md`), commit.
5. `helm lint charts/stock-hpp` and
   `helm template charts/stock-hpp -f charts/stock-hpp/values.yaml -f charts/stock-hpp/values-dev.yaml`
   locally to sanity-check the chart renders before handing it to Argo CD.
6. `cd terraform/environments/dev && terraform init && terraform apply`, then
   the same in `terraform/environments/staging`, to register both
   Applications with Argo CD.

**Phase 1 — dev, fully automated**
1. PR merged to `stock-backend`/`stock-frontend` `main`.
2. Existing CI builds/tests/scans, pushes `:<sha>`/`:dev`/`:staging` (unchanged).
3. New CI job (`bump-dev.yml`), triggered after `push-image`: checks out
   `stock-infrastructure`, bumps `charts/stock-hpp/values-dev.yaml`'s
   `backend.image.tag`/`frontend.image.tag` field with `yq eval -i`, opens a
   PR, **auto-merges it** immediately.
4. `dev-app`'s `syncPolicy.automated: {prune: true, selfHeal: true}` picks up
   the new commit, Argo CD re-renders the chart with the new values, runs the
   PreSync migration Job, then rolls the Deployment.
5. Dev is running the new image, zero human steps.

**Phase 2 — staging, human-gated promotion**
1. Same bump-job pattern targets `charts/stock-hpp/values-staging.yaml`,
   opens a PR, **does not auto-merge**.
2. A human reviews/merges when ready to promote — this is the deliberate
   environment-promotion gate ("progressive delivery, minus canary analysis").
3. `staging-app` only syncs once that PR lands.

**Phase 3 — future/optional, not built now**
Add **Argo Rollouts** (same project family as Argo CD — incremental install,
not a re-architecture). Swap the chart's `Deployment` templates for `Rollout`
templates with a canary strategy using **Traefik's weighted
`TraefikService`** (already present via k3s) as the traffic-splitting
backend. Needs a metrics source (Prometheus, also free/OSS) for
`AnalysisTemplate`-driven auto-rollback; until then, promotion stays exactly
the Phase 1/2 model. Argo Rollouts' CRDs render fine through the same Helm
chart/Argo CD pipeline — no packaging change needed to adopt it later.

## Verification

- **Phase 0**: `kubectl get nodes` Ready; `kubectl get pods -n argocd` all
  Running; Argo CD UI reachable via port-forward; a round-trip `kubeseal`
  encrypt/decrypt of a test secret succeeds; `helm template` renders without
  error for both `values-dev.yaml` and `values-staging.yaml`.
- **Phase 1**: after a trivial backend PR merge — CI green through
  `push-image` → `bump-dev` PR appears and auto-merges (`gh pr list --repo
  <org>/stock-infrastructure`) → Argo CD `dev-app` goes
  `OutOfSync`→`Progressing` (PreSync Job visible)→`Synced`/`Healthy` →
  `kubectl get jobs -n stock-hpp-dev` shows the migrate Job `Completed` →
  port-forward the backend Service and `curl localhost:8000/healthz`
  (`/healthz` is mounted at the backend's root, not under `/api`, so it
  isn't reachable through the Ingress's host-based routing — see
  `runbook.md` §1.9) and check pod age
  (`kubectl get pods -n stock-hpp-dev -o wide`) confirms the new rollout.
- **Phase 2**: confirm the staging bump PR sits open (CI green, unmerged);
  merge it by hand; confirm `staging-app` only transitions afterward; confirm
  dev and staging report different image tags simultaneously
  (`kubectl get deploy -n stock-hpp-<env> -o jsonpath='{.spec.template.spec.containers[0].image}'`).
- **Phase 3 (when built)**: `kubectl argo rollouts get rollout <name> -n
  stock-hpp-staging --watch` shows weighted traffic steps; an intentionally
  broken image triggers automatic rollback once `AnalysisTemplate` +
  Prometheus are wired in.

## Critical files referenced

- `stock-backend/Dockerfile` (clean `CMD`, line 61) — image the PreSync Job reuses.
- `stock-backend/docker-compose.yml` (lines 46–49) — pattern Fix A replaces in k8s, left as-is for local dev.
- `stock-frontend/Dockerfile`, `stock-frontend/nginx.conf` — where Fix B's entrypoint script and `config.js` templating are added.
- `stock-frontend/src/api/client.ts:6` — runtime-injected `API_BASE_URL` integration point.
- `stock-backend/app/main.py:30` — `/healthz`, the recommended `/readyz` companion fix.
- `stock-backend/.github/workflows/ci.yml`, `stock-frontend/.github/workflows/ci.yml` — where `bump-dev`/`bump-staging` jobs append after the existing `push-image` job.
- `stock-infrastructure/infrastructure.md`, `stock-infrastructure/CLAUDE.md` — prior-art blocker list this plan resolves, and the governance rules (PR-only workflow, shared `.gitignore` baseline) every new file must keep satisfying.
