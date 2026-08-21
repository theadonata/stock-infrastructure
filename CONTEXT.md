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

**Monitoring stack**:
The shared Prometheus + Grafana + Loki + Alloy + Alertmanager deployment in
the `monitoring` namespace (see `0003-observability-stack.md`), synced from
one single-source Argo CD Application. One instance covers both
`stock-hpp-dev` and `stock-hpp-staging` — it is not duplicated per
environment the way the app itself is. Does not include tracing (Tempo is
deferred until an app actually emits traces).
_Avoid_: "observability stack" as a project-specific term — fine as a
general description, but "monitoring stack"/"the monitoring namespace" is
what this project actually calls it, matching the namespace/Application
name.
