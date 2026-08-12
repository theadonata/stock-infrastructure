# Kubernetes deployability & scalability assessment

Date: 2026-08-12

Reviews the current `stock-backend`/`stock-frontend` architecture against
the design spec's stated target (self-hosted Kubernetes on a VPS) and asks
two questions: can this actually be deployed to k8s, and is it scalable?
This is an assessment, not an implementation — no k8s manifests exist yet
and none are proposed in detail here (per this repo's `CLAUDE.md`: don't
scaffold a platform/tool choice that hasn't been made).

## Verdict

**Yes, deployable to Kubernetes** — the architecture is fundamentally
sound for it: independent per-service Docker images, fully env-driven
config, non-root containers, and a stateless backend. **Not yet
scalable/production-ready as-is**, though — a handful of concrete gaps
need to close first, listed below. None of them are architectural
rewrites; they're deployment-process fixes.

## What's already Kubernetes-ready

- **Independent images per service** — `stock-backend` and `stock-frontend`
  each own their own `Dockerfile`, built and published independently, with
  no shared build context or path dependency between them. This matches
  k8s's expectation of independently deployable/scalable units directly.
- **Fully env-driven config** — `DATABASE_URL`, `JWT_SECRET`,
  `JWT_ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `CORS_ORIGINS`,
  `SEED_ADMIN_USERNAME`/`PASSWORD` are all read from environment variables
  (`app/core/config.py`, pydantic-settings). Maps directly onto a
  ConfigMap (non-secret values) + Secret (`JWT_SECRET`, DB credentials)
  with no code changes needed.
- **Non-root container** — the backend image creates and runs as
  `appuser` (`useradd --create-home --uid 1000 appuser` / `USER appuser`
  in the Dockerfile), which satisfies a typical k8s
  `securityContext.runAsNonRoot: true` policy out of the box.
- **Stateless backend** — auth is JWT-only with no server-side session
  store (`decode_access_token` just verifies the token's signature/claims);
  DB access goes through a per-request session (`get_db()` in
  `app/db/session.py`) that's always closed in a `finally` block, with
  `pool_pre_ping=True` guarding against stale connections after a DB
  pod/network blip. No in-process mutable state (caches, session stores,
  rate-limit counters) was found anywhere in `app/` that would behave
  differently across multiple replicas.
- **A liveness endpoint already exists** — `GET /healthz` in `app/main.py`,
  deliberately DB-free so it stays cheap, matching k8s's liveness-probe
  expectations.
- **Frontend is a static SPA behind nginx** — once built, it's just static
  files served by nginx with SPA-fallback routing
  (`try_files $uri $uri/ /index.html` in `nginx.conf`). Trivially
  horizontally scalable — any number of identical replicas behind a
  Service work with no coordination needed.

## Blockers to fix before deploying to k8s

Each of these is a real gap found in the current code/compose setup, not a
hypothetical:

1. **Migration execution is coupled to pod startup, and will race under
   multiple replicas.** Today, migrations only run automatically because
   `stock-backend/docker-compose.yml`'s `command:` chains
   `alembic upgrade head && uvicorn app.main:app ...` — the Dockerfile's
   own `CMD` is just uvicorn, with no migration step. If that same
   compose `command:` were reused verbatim as a Deployment's pod command
   with `replicas > 1`, every pod would run `alembic upgrade head`
   concurrently on every rollout/restart — a real race condition against
   the same database. **Fix**: move migrations into a one-time Job (or a
   Helm/Kustomize pre-install/pre-upgrade hook) that runs once per
   release, before the Deployment rolls out; the Deployment's pods should
   only run uvicorn.

2. **No readiness probe exists.** `/healthz` is intentionally liveness-only
   (no DB check). Without a separate readiness check, k8s has no way to
   know a pod can't reach Postgres before routing traffic to it — e.g. on
   startup before the DB is reachable, or after a DB connection issue.
   **Fix**: add a `/readyz` endpoint that does a lightweight DB ping (e.g.
   `SELECT 1`), and configure the k8s readiness probe against it,
   separately from the liveness probe against `/healthz`.

3. **The frontend's backend URL is baked in at Docker build time, not
   runtime.** `VITE_API_BASE_URL` is a Vite env var, which Vite inlines
   into the built JS bundle at `npm run build` time (confirmed in
   `stock-frontend/Dockerfile`'s `ARG`/`ENV` lines and
   `src/api/client.ts`'s `import.meta.env.VITE_API_BASE_URL` read). There
   is no entrypoint script that injects it at container start. Practical
   effect: **one built frontend image is permanently tied to one backend
   URL** — you cannot build once and promote the same image across
   dev/staging/prod with different backend targets; each environment
   needs its own build. **Fix, pick one**: (a) accept a separate build per
   environment (simplest, reasonable for a small internal tool with few
   environments), or (b) add a runtime-injection entrypoint — e.g. an
   nginx `envsubst` step that templates a small `/config.js` (containing
   the backend URL) fetched at page load, decoupling the image from the
   target environment.

4. **The admin-seeding script isn't part of any automated flow.**
   `scripts/seed_admin.py` is a manual, idempotent one-off
   (`docker compose exec ... python -m scripts.seed_admin` today). In k8s
   this should become a one-time Job run after the migration Job
   completes (or stay a manual `kubectl exec` for a single-admin internal
   tool) — it must not be added to steady-state pod startup, or every pod
   restart would attempt to re-seed.

5. **Dev-placeholder secrets must not reach a real cluster.** `JWT_SECRET`
   defaults to `"CHANGE_ME_INSECURE_DEV_ONLY_SECRET"` and
   `SEED_ADMIN_PASSWORD` defaults to `"changeme123"` in
   `app/core/config.py`/`.env.local` — intentionally obvious placeholders
   for local dev. These need to come from real k8s Secrets before any real
   deployment. Already tracked in detail in
   `stock-business-analyst/findings.md`; not re-litigated here.

6. **`CORS_ORIGINS` defaults to `*`.** Must be set (via ConfigMap/env var)
   to the actual Ingress-exposed frontend origin once one exists — also
   already tracked in `findings.md`.

## Scalability assessment

- **Backend**: horizontally scalable via a standard Deployment +
  HorizontalPodAutoscaler (on CPU or request latency) *once* the
  migration-race (#1) and readiness-probe (#2) gaps above are closed —
  those are precisely the things that make naive multi-replica scaling
  unsafe today. One additional tuning note: SQLAlchemy's engine
  (`app/db/session.py`) uses the library's default connection pool size
  (5, unconfigured) — as replica count grows, `replicas × pool_size` needs
  to stay under Postgres's `max_connections`, so pool size should be set
  explicitly and sized deliberately once real replica counts are decided.
- **Frontend**: trivially scalable — stateless static assets behind nginx,
  no per-replica coordination needed. The build-time backend-URL binding
  (blocker #3) is a deployment-*process* concern (how many images you
  build and when), not a runtime scaling concern.
- **Database**: this is the real scaling ceiling and single point of
  failure in the current design. Per the design spec, Postgres hosting is
  an explicitly open decision — either an in-cluster StatefulSet+PVC or an
  external managed/self-hosted instance — and the backend only depends on
  a connection string either way, so this choice doesn't require backend
  code changes. That said, it's the one piece of this architecture that
  doesn't horizontally scale by just adding replicas, and the decision
  belongs to `stock-infrastructure` once it's scoped, not made
  unilaterally here.

## Suggested target shape (naming only — not manifests)

- `Deployment` + `Service` + `HorizontalPodAutoscaler` for `stock-backend`
- `Deployment` + `Service` + `HorizontalPodAutoscaler` for `stock-frontend`
- A one-time `Job` for `alembic upgrade head` (run before each release's
  Deployment rollout); optionally a separate `Job` for admin seeding
- `Ingress` in front of both services (HTTPS termination/routing)
- `ConfigMap` for non-secret env vars (`CORS_ORIGINS`,
  `ACCESS_TOKEN_EXPIRE_MINUTES`, etc.), `Secret` for credentials
  (`JWT_SECRET`, `DATABASE_URL`, `SEED_ADMIN_PASSWORD`)
- Postgres as either an in-cluster `StatefulSet` + `PersistentVolumeClaim`
  or an external managed/self-hosted instance — open decision, see below

## Not decided here — needs input

These are genuine open decisions, not something this assessment should
make unilaterally (consistent with this repo's `CLAUDE.md`: ask before
scaffolding a platform/tool choice):

- Cloud provider vs. bare VPS, and which k8s distribution (k3s, kubeadm,
  etc.) — nothing has been chosen yet.
- Postgres hosting: in-cluster StatefulSet vs. external managed/self-hosted
  instance.
- Whether to build the runtime env-injection mechanism for the frontend
  now (blocker #3, option b) or accept a per-environment build (option a)
  for now and revisit later.

Flagging these in `stock-business-analyst/questions.md` rather than
deciding them here.
