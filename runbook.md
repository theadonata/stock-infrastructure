# Runbook — stock-hpp GitOps cluster

Copy-paste commands. Lines starting with `#` in a code block are comments —
don't type those. Stuck? Jump to **§7 Troubleshooting**.

**One-time GitHub setup for automatic image promotion** (§0.3) — without
it, `bump-dev`/`bump-staging` CI jobs fail and image promotion falls back to
a manual PR (§2). Everything else (bootstrap, syncing, rollback, secrets)
works without it.

## Contents
0. [Prerequisites](#0-prerequisites)
1. [First-time bootstrap](#1-first-time-cluster-bootstrap)
2. [Deploying a change](#2-deploying-a-change)
3. [Promoting dev → staging](#3-promoting-dev--staging)
4. [Rolling back](#4-rolling-back-a-bad-deploy)
5. [Rotating a secret](#5-rotating-a-secret-password-jwt-key-etc)
6. [Scaling](#6-scaling-up-running-more-copies-of-the-app)
7. [Troubleshooting](#7-troubleshooting)
8. [Known gaps](#8-things-that-arent-solved-yet-know-these-before-you-rely-on-this)
9. [Adding an environment](#9-adding-a-new-environment-eg-production)
10. [Monitoring stack — deploying Prometheus & Grafana](#10-monitoring-stack--deploying-prometheus--grafana)
11. [Glossary](#glossary)

---

## How this works

Config in this repo describes what the app *should* look like. You PR a
change to `main`; **Argo CD**, running in-cluster, notices and applies it.
This is **GitOps** — git is the source of truth, a robot applies it. You
rarely run raw `kubectl apply`.

| Piece | What it is |
|---|---|
| Kubernetes / k3s | Runs containers, keeps them running. k3s = lightweight K8s for a single machine. |
| Container image | Pre-built app copy on `ghcr.io`, pushed by CI in `stock-backend`/`stock-frontend`. |
| Helm chart (`charts/stock-hpp/`) | One template + per-env `values-<env>.yaml` override generates all the K8s YAML. |
| Argo CD | Watches this repo, applies changes. One **Application** per env (dev, staging) plus one shared monitoring Application. |
| Terraform / Terragrunt | Sets up k3s (optional), Argo CD, Sealed Secrets, repeatably. Terragrunt orchestrates every layer — plain `terraform` won't work here. |
| Sealed Secrets | Encrypts secrets so the ciphertext is safe to commit; only this cluster can decrypt. |
| Namespace | K8s "folder" — `stock-hpp-dev`, `stock-hpp-staging`, `monitoring`. |

Unfamiliar term later on? Check the [Glossary](#glossary).

**Two modes:** §1 is a one-time, ~20–30 min bootstrap — go slowly. §2
onward is day-to-day stuff, mostly short — read as needed.

---

## 0. Prerequisites

| Tool | Check | For |
|---|---|---|
| `kubectl` | `kubectl version --client` | Talk to the cluster |
| `helm` | `helm version` | Validate the chart |
| `terraform` ≥1.9 | `terraform version` | Underlying engine (see below) |
| `terragrunt` | `terragrunt --version` | Orchestrates Terraform across `k3s`/`bootstrap`/`dev`/`staging`/`monitoring` — **required**, not optional |
| `kubeseal` | `kubeseal --version` | Encrypt secrets before committing |

`~/.kube/config` gets created in §1 step 1 — nothing to do yet.

### 0.1 Passwordless sudo (only if k3s runs on this machine)

Terraform runs unattended, so it needs `sudo` for three specific commands
without a password prompt. One-time setup, run yourself (not automatable):

```bash
cat <<EOF | sudo tee /etc/sudoers.d/k3s-terraform
$(whoami) ALL=(root) NOPASSWD: /usr/bin/sh $HOME/.cache/k3s-install.sh, /usr/bin/cat /etc/rancher/k3s/k3s.yaml, /usr/local/bin/k3s-uninstall.sh
EOF
sudo chmod 440 /etc/sudoers.d/k3s-terraform
sudo visudo -c
```

This grants passwordless install/read/**uninstall** access to *any* process
running as your user — real access, scoped to exactly those three commands.
Fine for a single-operator machine; see `terraform/README.md` §0 for the
full reasoning. Confirm:
```bash
sudo -n -l | grep k3s-uninstall.sh   # should print a line listing all 3 commands
```

### 0.2 Pushing changes

Every change goes through a GitHub PR — never directly to `main` (see
`CLAUDE.md`). You'll need push access to `stock-infrastructure`.

### 0.3 Enabling automatic image promotion (one-time)

`stock-backend`/`stock-frontend` CI bumps image tags here and opens a PR
automatically after merging to their `main`. Needs:

1. **Mint a fine-grained PAT** at `github.com/settings/personal-access-tokens/new`
   — this repo only, Contents (R/W) + Pull requests (R/W). Don't reuse a PAT
   used elsewhere (`docs/adr/0001-cross-repo-bump-credential.md`).
2. **Add it as secret `INFRA_REPO_PAT`** in both `stock-backend` and
   `stock-frontend` repo settings (Settings → Secrets and variables →
   Actions).
3. **In `stock-infrastructure` settings:** enable "Allow auto-merge"
   (Settings → General), and add this repo's CI job names — `secret-scan`,
   `terraform-fmt`, `terraform-validate`, `helm`, `shellcheck`,
   `dependency-review`, `iac-scan`, `sonarcloud` — to `main`'s
   required-status-checks (Settings → Branches).

---

## 1. First-time cluster bootstrap

Do these in order; fix any failure before continuing (§7).

**Shortcut:** `scripts/bootstrap-cluster.sh` runs steps 1, 2, 6, 7 for you
(and step 4's secret generation from `.env.local`), pausing only to confirm
you've done step 3's key backup by hand. Read it first
(`./scripts/bootstrap-cluster.sh --help`). Use `--skip-k3s` if the cluster
runs on a separate machine. Reading §1 once, even if you use the script, is
still worth it — you'll need to understand it to debug anything.

1. **Install k3s.** Same machine:
   ```bash
   cd terraform/environments/k3s
   terragrunt init
   terragrunt apply   # needs §0.1's sudo setup
   ```
   Separate machine: follow `bootstrap/k3s-install.md` there instead.
   Confirm:
   ```bash
   kubectl get nodes                 # one node, STATUS = Ready
   kubectl get pods -n kube-system   # Traefik + local-path-provisioner Running
   ```

2. **Install Argo CD + Sealed Secrets:**
   ```bash
   cd terraform/environments/bootstrap
   terragrunt init
   terragrunt apply
   ```
   Non-default kubeconfig path? Use
   `TF_VAR_kubeconfig_path=/path/to/kubeconfig terragrunt apply` (see
   `terraform/modules/bootstrap-environment/variables.tf`).
   Confirm:
   ```bash
   kubectl get pods -n argocd            # all Running
   kubectl get pods -n sealed-secrets    # controller Running
   ```
   Can take a couple minutes (first-time image pulls).

3. **Back up the Sealed Secrets private key** — the *only* thing that can
   decrypt every secret you're about to commit:
   ```bash
   kubectl get secret -n sealed-secrets \
     -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
     > ~/sealed-secrets-key-backup.yaml
   ```
   Written to your home directory, not the repo — this is the *unencrypted*
   key. Move it off this machine (password manager, encrypted USB), then
   delete the local copy.

4. **Generate each environment's secrets.** Real values already live in
   `.env.local` (`DEV_POSTGRES_PASSWORD`/`DEV_JWT_SECRET`/`STAGING_*`):
   ```bash
   ./scripts/generate-secrets.sh dev
   ./scripts/generate-secrets.sh staging
   ```
   Plaintext never touches disk — only the encrypted result lands in
   `secrets/{dev,staging}/backend-secrets.sealed.yaml`. Commit both via PR.
   Rotate values in `.env.local`, not the `.sealed.yaml` files — see
   `secrets/dev/README.md` for the manual `kubeseal` command this wraps.

5. **Sanity-check the chart:**
   ```bash
   helm lint charts/stock-hpp -f charts/stock-hpp/values.yaml -f charts/stock-hpp/values-dev.yaml
   helm template charts/stock-hpp -f charts/stock-hpp/values.yaml -f charts/stock-hpp/values-dev.yaml
   ```
   Expect "0 chart(s) failed"; `helm template`'s YAML dump is expected.

6. **Register the Applications:**
   ```bash
   cd terraform/environments/dev && terragrunt init && terragrunt apply
   cd ../staging && terragrunt init && terragrunt apply
   ```

7. **Verify:**
   ```bash
   kubectl get applications -n argocd
   # stock-hpp-dev      Synced   Healthy
   # stock-hpp-staging  <may show OutOfSync until step 8 — expected>
   ```

8. **Sync staging once, manually** — a deliberate safety gate (§3):
   ```bash
   kubectl patch application stock-hpp-staging -n argocd --type merge -p '{"operation":{"sync":{}}}'
   ```

9. **Confirm it's actually running:**
   ```bash
   kubectl get jobs -n stock-hpp-dev          # stock-hpp-backend-migrate: Complete
   kubectl get pods -n stock-hpp-dev -o wide  # all Running
   ```
   ```bash
   kubectl port-forward -n stock-hpp-dev svc/stock-hpp-backend 8000:8000 &
   curl http://localhost:8000/healthz   # {"status":"ok"}
   kill %1
   ```
   ```bash
   curl -I http://stock-hpp.dev.lan/   # HTTP/1.1 200 OK
   ```
   (`stock-hpp.dev.lan` needs DNS/hosts pointed at it — a resolve failure
   here is a DNS setup gap, not a broken deploy.)

🎉 **Dev is running and auto-deploys on every `values-dev.yaml` change.**
Staging waits for an explicit sync, same as step 8. Read on as needed.

---

## 2. Deploying a change

Fully automatic once §0.3 is done:

1. Merge in `stock-backend`/`stock-frontend` → CI builds, pushes images,
   bumps `values-dev.yaml` here, opens `bump-dev-*` PR.
2. That PR auto-merges once required checks pass (~1–2 min).
3. Argo CD notices and rolls out (migration, then the new version). Force
   an immediate check:
   ```bash
   kubectl patch application stock-hpp-dev -n argocd --type merge -p '{"operation":{"sync":{}}}'
   ```
4. Watch:
   ```bash
   kubectl get application stock-hpp-dev -n argocd -w
   kubectl get jobs -n stock-hpp-dev
   kubectl get pods -n stock-hpp-dev -o wide
   ```

**Manual fallback**, if the bump job isn't set up or is broken:
```bash
git fetch origin && git merge --ff-only origin/main
git checkout -b bump-dev-<short-sha>
yq eval -i '.backend.image.tag = "<sha>"' charts/stock-hpp/values-dev.yaml
# backend changed → also bump the db image tag, same commit (they move together):
yq eval -i '.postgres.image.tag = "<sha>"' charts/stock-hpp/values-dev.yaml
# (use .frontend.image.tag for a frontend change — no matching second field)
git add charts/stock-hpp/values-dev.yaml
git commit -m "bump dev backend image to <sha>"
git push -u origin bump-dev-<short-sha>
gh pr create --fill
```

---

## 3. Promoting dev → staging

1. Bump PRs against `values-staging.yaml` auto-merge the same way as dev —
   promotion to git happens on its own. No bump job set up? Same manual
   fallback as §2, targeting `values-staging.yaml`.
2. Staging still **won't deploy** until you say so — the actual gate:
   ```bash
   kubectl patch application stock-hpp-staging -n argocd --type merge -p '{"operation":{"sync":{}}}'
   ```
3. Confirm they're intentionally different:
   ```bash
   kubectl get deploy -n stock-hpp-dev -o jsonpath='{.items[*].spec.template.spec.containers[0].image}'
   kubectl get deploy -n stock-hpp-staging -o jsonpath='{.items[*].spec.template.spec.containers[0].image}'
   ```

---

## 4. Rolling back a bad deploy

**Best — undo in git:**
```bash
git revert <bad-bump-commit-sha>   # new branch + PR, as usual
```
Argo CD rolls the cluster back automatically (dev) or via manual sync (§3.2, staging).

**Faster but temporary** — use only when something's actively broken and a
revert PR can't land fast enough; fix the file in git afterward or it'll
drift:
```bash
argocd app history stock-hpp-dev
argocd app rollback stock-hpp-dev <history-id>
```
Dev self-heals back to whatever `values-dev.yaml` says on its next
check-in, undoing this unless you also fix the file.

**Broken migration:** the old version keeps running — Argo CD won't roll
out the new one until migration succeeds.
```bash
kubectl logs -n stock-hpp-dev job/stock-hpp-backend-migrate
```

---

## 5. Rotating a secret (password, JWT key, etc.)

**Preferred:** edit `.env.local` (`DEV_POSTGRES_PASSWORD`/`DEV_JWT_SECRET`/
`STAGING_*`), then:
```bash
./scripts/generate-secrets.sh <env>
```

**By hand**, if not keeping real values in `.env.local` — note the real
value lands in shell history as plain text (fine for a homelab; `history -d
<line>` after, or a leading space with `HISTCONTROL=ignorespace`):
```bash
kubectl create secret generic stock-hpp-backend-secrets \
  --namespace stock-hpp-<env> \
  --from-literal=POSTGRES_USER=stock_hpp_user \
  --from-literal=POSTGRES_PASSWORD='<new-password>' \
  --from-literal=POSTGRES_DB=stock_hpp_db \
  --from-literal=DATABASE_URL='postgresql+psycopg2://stock_hpp_user:<new-password>@stock-hpp-postgres:5432/stock_hpp_db' \
  --from-literal=JWT_SECRET='<new-or-existing-secret>' \
  --dry-run=client -o yaml | kubeseal --format yaml \
    --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
  > secrets/<env>/backend-secrets.sealed.yaml
```
PR it. After Argo CD syncs, **pods don't auto-notice** — restart by hand:
```bash
kubectl rollout restart deployment -n stock-hpp-<env> stock-hpp-backend
```
Rotating `POSTGRES_PASSWORD`? Change it on the database *first*
(`kubectl exec` into the postgres pod, `ALTER USER stock_hpp_user WITH
PASSWORD '...'`), then update the sealed secret — otherwise there's a
window where the backend's new password doesn't match the database.

---

## 6. Scaling up (running more copies of the app)

Replica counts live in `values.yaml` (`backend.replicaCount`,
`frontend.replicaCount`). Override per-environment in that env's
`values-<env>.yaml`, then PR. The database is intentionally single-copy —
see `docs/adr/0002-gitops-deployment-architecture.md` for why that's a real
limit, not a number you can just bump.

---

## 7. Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| App stuck `OutOfSync`/`Progressing` | Migration failed or hasn't finished | `kubectl get jobs -n stock-hpp-<env>`; `kubectl logs job/stock-hpp-backend-migrate -n stock-hpp-<env>` |
| App shows `Unknown`/`Degraded` | Chart failed to render / bad values file | `helm template` from §1.5 locally; `kubectl describe application <name> -n argocd` |
| Pods `ImagePullBackOff` | Image tag doesn't exist on `ghcr.io` yet | `kubectl describe pod <pod> -n stock-hpp-<env>`; confirm CI actually pushed it |
| Backend `CrashLoopBackOff` | Bad `DATABASE_URL`/`JWT_SECRET`, or DB not ready | `kubectl logs -n stock-hpp-<env> deploy/stock-hpp-backend` |
| Website 502/504 | No healthy backend/frontend pods | `kubectl get endpoints -n stock-hpp-<env>` |
| `kubeseal` fails | Wrong cluster context, or controller down | `kubectl get pods -n sealed-secrets`; `kubeseal --fetch-cert` |
| `terragrunt apply` (dev/staging) errors on missing "Application" CRD | `bootstrap` layer not applied / still starting | `kubectl get pods -n argocd` all Running, retry |
| CORS error in browser console | `CORS_ORIGINS` doesn't match the real hostname | Compare `backend.env.CORS_ORIGINS` vs `ingress.host` in that env's values file |
| `bootstrap` apply times out ("timed out waiting for condition") | First install pulling ~7 images, slower than the wait timeout — not a real failure | `kubectl get pods -n argocd` — all `1/1 Running`? Re-run `terragrunt apply`, shows "No changes" |
| `bootstrap-cluster.sh` hangs waiting for argocd pods Ready despite all showing Running | A one-shot Job pod (`argocd-redis-secret-init`) completes and stays `Ready=False` forever by design; older script copies wait for it anyway | Fixed in current script (excludes completed pods) — `git pull`/re-copy, or just check `kubectl get pods -n argocd` yourself |
| `terragrunt apply` in `k3s` fails on sudo/password | §0.1 setup missing or wrong | `sudo -n -l \| grep k3s-install.sh` — should list all 3 commands |
| `terragrunt destroy` in `k3s` hangs on sudo/password | Same, missing uninstall permission specifically | `sudo -n -l \| grep k3s-uninstall.sh` |
| Grafana/Alertmanager `CrashLoopBackOff`/`ContainerCreating` right after monitoring first syncs | §10's two SealedSecrets not generated/committed yet | `kubectl get secrets -n monitoring`; run `./scripts/generate-monitoring-secrets.sh` and PR it |
| Alertmanager not posting to Discord | Placeholder `DISCORD_WEBHOOK_URL` never replaced | `kubectl -n monitoring exec statefulset/alertmanager-monitoring-kube-prometheus-alertmanager -- cat /etc/alertmanager/config_out/alertmanager.env.yaml`; regenerate per §10 with a real webhook |
| No logs in Grafana's Loki datasource | Alloy down, or can't reach Loki | `kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy -o wide` (one per node); `kubectl logs -n monitoring -l app.kubernetes.io/name=alloy` |
| **WSL2 + Docker Desktop:** k3s never Ready, journal says `system validation failed - wrong number of fields (expected 6, got 7)` | Docker Desktop's WSL mount has an unescaped space in its path, breaking kubelet's mount-table parser. Known bug: [k3s-io/k3s#4483](https://github.com/k3s-io/k3s/issues/4483) | Confirm: `grep "Program Files" /proc/mounts`. Fix (Windows side): Docker Desktop → Settings → Resources → WSL Integration → turn **off** this distro's toggle → `wsl --shutdown` → reopen. Don't re-run the k3s install — just re-run `bootstrap-cluster.sh` |

---

## 8. Things that aren't solved yet (know these before you rely on this)

- **No database backup.** Single copy, local disk — disk failure loses
  data. Back it up yourself (e.g. scheduled `pg_dump`) if this matters.
- **Terraform state is local-only** to this machine
  (`terraform/root.hcl`'s `generate "backend"` explains why). Lose the
  machine, and a fresh `terragrunt apply` would try to recreate everything
  and collide with what already exists. Back up `terraform.tfstate` and the
  Sealed Secrets key (§1.3) together if this matters.
- **Rebuilding from nothing** = redo §1, or re-run
  `./scripts/bootstrap-cluster.sh` (safe — no-op per stage if nothing
  changed). App config comes back from git automatically; only the
  database's data and the Sealed Secrets key don't. To tear down first:
  ```bash
  ./scripts/destroy-cluster.sh
  ```
  Reverse order (staging → dev → bootstrap → k3s), asks you to type
  `DESTROY`, cleans up `~/.kube/config` after. `--keep-k3s` tears down just
  the app layer.

---

## 9. Adding a new environment (e.g. production)

`dev`/`staging`/`monitoring` share one root module
(`terraform/modules/app-environment/`) — adding one is just a new
`terragrunt.hcl`, not a directory of `.tf` files:

1. Copy `values-staging.yaml` → `values-production.yaml`; adjust image
   tags/hostname/CORS.
2. Copy `terraform/environments/staging/terragrunt.hcl` →
   `terraform/environments/production/terragrunt.hcl`, keeping `source`
   unchanged — update only `inputs` (namespace/app name, values files,
   secrets path).
3. `mkdir secrets/production`, generate its sealed secret (§5).
4. `cd terraform/environments/production && terragrunt init && terragrunt apply`.
5. Decide deliberately: auto-deploy, or manual sync like staging — don't
   just copy staging's choice unthinkingly.

---

## 10. Monitoring stack — deploying Prometheus & Grafana

One shared instance covers both `dev` and `staging` — not duplicated per
environment. Covers **Prometheus** (metrics), **Grafana** (dashboards, from
ConfigMaps — not hand-built in the UI), **Loki + Alloy** (logs),
**Alertmanager** (Discord alerts). No tracing yet (Tempo, deferred until
the apps emit traces). Full design: `docs/adr/0003-observability-stack.md`.

### Deploy it (first time)

Requires `terraform/environments/bootstrap` already applied (§1).

```bash
# 1. Set GRAFANA_ADMIN_PASSWORD and DISCORD_WEBHOOK_URL in .env.local
#    (see charts/monitoring/README.md), then generate both SealedSecrets:
./scripts/generate-monitoring-secrets.sh

# 2. PR charts/monitoring/templates/*.sealed.yaml, as usual.

# 3. Register the namespace + Argo CD Application:
cd terraform/environments/monitoring
terragrunt init
terragrunt apply
```

From here it auto-syncs like `dev` — every merge touching
`charts/monitoring/` rolls out with no further Terraform runs, unless the
Application's own definition changes (new values file, different target
revision).

### Access

**Grafana:** `http://grafana.dev.lan` (Traefik Ingress, same pattern as the
app itself). Log in `admin` / whatever `GRAFANA_ADMIN_PASSWORD` was set to.

**Prometheus / Alertmanager:** no Ingress by default — reach them via
port-forward:
```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

### Rotating credentials

Edit `.env.local`, re-run `./scripts/generate-monitoring-secrets.sh`, PR
the result — both secrets regenerate together, no per-secret variant.
Grafana needs a restart to notice a changed admin password:
```bash
kubectl rollout restart deployment -n monitoring monitoring-grafana
```
Alertmanager reloads its config on its own — no restart needed.

### Alerts

Alertmanager routes by **resource category** (a Discord channel per
category), not by severity — severity (`warning`/`critical`) only shows up
inside the message text. See `CONTEXT.md`'s "Alert severity"/
"Resource-category routing" entries before assuming an alert has its own
channel: most of kube-prometheus-stack's 150+ built-in default alerts
(`KubePodCrashLooping`, `KubePersistentVolumeFillingUp`, etc.) are *not*
categorized and still land on the flat `discord` receiver.

**`PodCPUUsageHigh`** (`charts/monitoring/templates/pod-cpu-usage-alert-rule.yaml`)
— the first, and so far only, alert routed by category:
- Fires per-container, when usage exceeds a percentage of that container's
  own CPU *limit*, sustained (not a rate-of-change/anomaly check):
  `warning` at 85% for 10m, `critical` at 95% for 5m.
- Goes to the `discord-cpu-memory` receiver/channel, separate from every
  other alert's `discord` channel — needs its own webhook: set
  `CPU_MEMORY_DISCORD_WEBHOOK_URL` in `.env.local` (create the Discord
  channel first, then Integrations → Webhooks there), same rotation
  process as above.
- **When it fires:** check which pod/namespace/container is named in the
  message, then `kubectl top pod -n <namespace> <pod>` and the "Kubernetes
  / Compute Resources / Pod" Grafana dashboard to see if it's a genuine
  sustained load increase (traffic, a slow query, a stuck loop) or just
  that container's limit being set too tight for normal peak load. If it's
  the latter, raise the limit in `charts/stock-hpp/values.yaml` rather than
  treating it as an incident.
- Adding more categorized alerts later: give the new `PrometheusRule`'s
  labels a `resource_category` value, add a matching route + receiver in
  `scripts/generate-monitoring-secrets.sh`'s `alertmanager_config` (and
  mirror it in `charts/monitoring/README.md`'s by-hand example), and a new
  `..._DISCORD_WEBHOOK_URL` var in `.env.local`.

---

## Glossary

- **Pod** — smallest running unit; usually one container copy.
- **Deployment** — manages a set of identical Pods, handles rollouts.
- **Job** — runs once to completion (used here for DB migration).
- **Service** — stable address routing to healthy Pods.
- **Ingress** — maps an external hostname/path to an internal Service.
- **ConfigMap / Secret** — config values; Secret for sensitive ones.
- **StatefulSet** — like a Deployment, but for stable identity/storage (DB).
- **PVC** — a disk-storage request that survives Pod restarts.
- **CRD** — how a tool (e.g. Argo CD) adds new object types like "Application".
- **Sync** — Argo CD's term for "make the cluster match git."
- **Rollout** — replacing old Pods with new ones on a Deployment change.
- **Metrics / logs / traces** — numbers over time (Prometheus), text lines
  (Loki), cross-service request tracking (not set up yet — §10).
- **Receiver** — Alertmanager's term for "where to send an alert" (Discord).

---

## Quick reference

```bash
# Full first-time bootstrap (§1) — preview only
./scripts/bootstrap-cluster.sh --plan-only

# Full teardown, reverse order — preview only
./scripts/destroy-cluster.sh --plan-only

# Namespaces / Applications
kubectl get applications -n argocd
kubectl get pods -n stock-hpp-dev -o wide
kubectl get pods -n stock-hpp-staging -o wide
kubectl get pods -n monitoring -o wide

# Force a sync
kubectl patch application stock-hpp-<env> -n argocd --type merge -p '{"operation":{"sync":{}}}'

# Migration Job status/logs
kubectl get jobs -n stock-hpp-<env>
kubectl logs -n stock-hpp-<env> job/stock-hpp-backend-migrate

# Current running image per environment
kubectl get deploy -n stock-hpp-<env> -o jsonpath='{.items[*].spec.template.spec.containers[0].image}'

# Terraform, per layer
for env in k3s bootstrap dev staging monitoring; do
  (cd terraform/environments/$env && terragrunt plan)
done
# ...or all at once, in dependency order:
cd terraform/environments && terragrunt run --all --non-interactive -- plan -input=false -lock=false
```
