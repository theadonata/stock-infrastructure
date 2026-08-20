# Getting started & operations runbook — stock-hpp GitOps cluster

Written for someone who's never worked with Kubernetes/DevOps before but
wants to get this stack running on their own machine. Every command below
is meant to be copied and pasted exactly. Lines starting with `#` inside a
code block are comments explaining what the line does — you don't type
those, just the rest.

If you get stuck at any point, jump to **§7 Troubleshooting** near the
bottom — it lists the most common things that go wrong and how to check
what's happening.

**One-time GitHub setup needed for automatic image promotion:** the
`bump-dev`/`bump-staging` CI jobs (per
`docs/adr/0002-gitops-deployment-architecture.md`) exist in
`stock-backend`'s/`stock-frontend`'s `.github/workflows/ci.yml`, but they
depend on account/repo settings a script can't set up for you — a PAT,
a secret, and a couple of GitHub UI toggles. See §0 "Enabling automatic
image promotion" below. Until that's done once, those jobs will fail rather
than silently doing nothing — image promotion (§2/§3) falls back to the
manual PR flow documented there in the meantime. Everything else in this
runbook — bootstrap, Argo CD syncing, rollback, secret rotation — works
today regardless.

---

## What is this, in plain English?

This repo takes the stock-hpp app — a backend API, a frontend website, and
a database — and runs it on your own machine using **Kubernetes**, a
system designed to run apps in containers and keep them running (restarting
them if they crash, routing traffic to them, etc.).

You don't deploy the app by typing deploy commands. Instead:

1. Config files in this repo describe what the app *should* look like
   (which container image to run, how many copies, what settings).
2. You push those files to GitHub as a pull request.
3. A tool called **Argo CD**, running inside the cluster, constantly
   watches this repo. When it sees a change land on `main`, it
   automatically updates the cluster to match.

This pattern is called **GitOps** — "git is the source of truth, and a
robot applies it for you." It's why you'll see very few raw `kubectl
apply` commands below: most of what you actually *do* is edit a file and
open a pull request, and the cluster catches up on its own.

### The pieces, one at a time

- **Kubernetes** — software that runs containers and manages them for you:
  restarts crashed ones, load-balances traffic between copies, etc.
- **k3s** — a lightweight version of Kubernetes made for small setups like
  a single homelab machine. This is what actually gets installed on your
  computer.
- **Container image** — a packaged, ready-to-run copy of the app (backend,
  frontend, or database), already built and pushed to `ghcr.io` (GitHub's
  container registry) by CI in the other `stock-*` repos.
- **Helm chart** — a template for a set of Kubernetes config files. Instead
  of hand-writing a dozen near-identical YAML files for dev and another
  dozen for staging, one chart (`charts/stock-hpp/`) plus a small
  per-environment override file (`values-dev.yaml`, `values-staging.yaml`)
  generates all of them.
- **Argo CD** — the "robot" described above. An **Application**, in Argo CD
  terms, is just "this path in this git repo maps to this thing running in
  the cluster." This repo has two: one for dev, one for staging.
- **Terraform** — a tool for setting up infrastructure in a repeatable,
  scripted way, instead of clicking around a UI or typing one-off commands
  you'll forget later. Here it sets up k3s itself (optionally), Argo CD,
  and the secrets-encryption tool below.
- **Sealed Secrets** — a safe way to store passwords/API keys inside git.
  Normally you'd never commit a real password (anyone with repo access
  could read it) — Sealed Secrets encrypts it first, so what actually gets
  committed is unreadable gibberish that only your specific cluster can
  decrypt.
- **Namespace** — think of it as a folder inside Kubernetes. This repo uses
  one namespace for dev (`stock-hpp-dev`) and one for staging
  (`stock-hpp-staging`) so the two don't interfere with each other.

If a term shows up later that isn't explained above, check the
**Glossary** near the bottom of this doc.

### Two very different modes in this document

- **§1, "First-time cluster bootstrap"** — you do this **once**, to stand
  the whole thing up for the first time. It's the longest, most technical
  part. Go slowly — it's completely normal for this to take 20–30 minutes
  the first time.
- **Everything after that (§2 onward)** — the things you'll actually do day
  to day once the cluster exists: deploying a code change, checking on
  things, fixing a problem. Most of these are short. You don't need to read
  them now — come back once you have something running.

If you're brand new to this, focus on **§0** and **§1** first.

---

## 0. Prerequisites

A few command-line tools need to be installed before any of this works.
Check whether you already have them by running each `--version` command
below — if you see a version number instead of "command not found", you're
set:

| Tool | Check with | What it's for |
|---|---|---|
| `kubectl` | `kubectl version --client` | Talks to the Kubernetes cluster — checking status, viewing logs, etc. This is the tool you'll use the most. |
| `helm` | `helm version` | Works with the Helm chart. Mostly used here to double-check the chart is valid before Argo CD uses it. |
| `terraform` (>= 1.9) | `terraform version` | Sets up Argo CD, Sealed Secrets, and (optionally) k3s itself, in a repeatable way. |
| `kubeseal` | `kubeseal --version` | Encrypts secrets (passwords, API keys) before they're safe to put in git. |

**`~/.kube/config`** — a file that tells `kubectl` and `terraform` which
cluster to talk to and how to log in to it (think of it as a saved login).
It gets created for you in §1 step 1 below — you don't need to do anything
about it yet.

**Only if the Kubernetes cluster will run on this same machine** (i.e. you
plan to use `terraform/environments/k3s` in §1 step 1, not a separate
box): Terraform needs limited permission to run a few commands as an
administrator (`sudo`) without stopping to ask for your password each
time. This is because Terraform runs unattended — it can't pause mid-run
and wait for you to type a password into a hidden prompt. Set this up
**once**, before that first `terraform apply`:

```bash
cat <<EOF | sudo tee /etc/sudoers.d/k3s-terraform
$(whoami) ALL=(root) NOPASSWD: /usr/bin/sh $HOME/.cache/k3s-install.sh, /usr/bin/cat /etc/rancher/k3s/k3s.yaml, /usr/local/bin/k3s-uninstall.sh
EOF
sudo chmod 440 /etc/sudoers.d/k3s-terraform
sudo visudo -c   # checks the file's syntax is valid before it takes effect
```

Run this yourself in a normal terminal (not something that can be
automated for you) so you can type your password when `sudo tee` asks for
it. This grants passwordless access to exactly three specific commands —
installing k3s, reading its config file, and uninstalling it — not general
admin access, but it's still real: any process running as your user (not
just Terraform) can now run those three commands, including the
**uninstaller**, without a password. Reasonable to accept on a
single-operator machine, but worth knowing rather than glossing over. See
`terraform/README.md` §0 for the full reasoning. Confirm it worked:
```bash
sudo -n -l | grep k3s-uninstall.sh
```
(grep for `k3s-uninstall.sh` — that's the command `terraform destroy` in
`terraform/environments/k3s` depends on to run non-interactively, so it's
worth confirming specifically, not just install/read. The string
`k3s-terraform` only appears in the sudoers *file's name*
(`/etc/sudoers.d/k3s-terraform`), never in what `sudo -l` actually prints,
so grepping for that finds nothing even when the rule is set up
correctly — `k3s-install.sh` works too, all three commands are on the same
line). If the command above prints a line listing all three commands,
you're done with this step.

**Pushing changes to this repo** — every change below that edits a file in
this repo goes through a GitHub **pull request (PR)**: GitHub's way of
proposing a change and reviewing it before it takes effect, rather than
editing the live version directly. You'll need push access to
`stock-infrastructure` on GitHub, and per this repo's `CLAUDE.md`, changes
never go directly to the `main` branch — always a new branch + PR.

**Enabling automatic image promotion (one-time).** `stock-backend`'s and
`stock-frontend`'s CI bump the image tag(s) in `values-dev.yaml`/
`values-staging.yaml` and open a PR here automatically after every merge to
their `main` — dev's PR auto-merges immediately, staging's waits for you to
review it (see §2/§3). This needs three things set up once, none of which a
file in this repo can do for you — they're GitHub account/repo settings:

1. **Mint a fine-grained PAT** at
   `github.com/settings/personal-access-tokens/new` — Resource owner: your
   account, Repository access: only `stock-infrastructure`, Permissions:
   Contents (Read and write), Pull requests (Read and write). Don't reuse a
   PAT used for anything else (see `docs/adr/0001-cross-repo-bump-credential.md`
   for why) — mint a fresh one for exactly this.
2. **Add it as a secret** named `INFRA_REPO_PAT` in both `stock-backend`'s
   and `stock-frontend`'s repo settings (Settings → Secrets and variables →
   Actions → New repository secret) — same value, both repos.
3. **In `stock-infrastructure`'s own repo settings:** turn on "Allow
   auto-merge" (Settings → General → Pull Requests), and add this repo's
   CI job names — `secret-scan`, `terraform-fmt`, `terraform-validate`,
   `helm`, `shellcheck`, `dependency-review`, `iac-scan`, `sonarcloud` — to
   `main`'s required-status-checks list (Settings → Branches → Branch
   protection rules). Without required checks, a bump PR has nothing to
   gate its auto-merge on.

---

## 1. First-time cluster bootstrap

Do these in order — each step assumes the previous one succeeded. If
something fails partway through, stop and fix it (see §7) before moving
on; later steps assume earlier ones actually worked.

**Shortcut:** `scripts/bootstrap-cluster.sh` runs steps 1, 2, 6, and 7
below for you in order (`terraform init`/`apply` in `k3s` →
`bootstrap` → `dev` → `staging`), instead of `cd`-ing into each
`terraform/environments/<env>` directory by hand. It also generates step
4's sealed secrets automatically from `.env.local` (see step 4 below) —
the only thing it still pauses for is confirming you've done step 3's key
backup by hand, which genuinely can't be read from a config file. Read it
before running it (`less scripts/bootstrap-cluster.sh` or
`./scripts/bootstrap-cluster.sh --help`) so you know what it's about to
do — it still installs k3s and stands up the whole cluster for real, same
as doing each step below by hand. Reading through steps 1–9 once, the
first time, is still worth it even if you use the script — it's what the
script is automating, and you'll need to understand it to debug anything
that goes wrong. If the cluster runs on a separate machine, use
`./scripts/bootstrap-cluster.sh --skip-k3s` instead.

1. **Install k3s** — this turns your machine into a single-node Kubernetes
   cluster. If the cluster will run on this same machine (the usual case
   for a first-time local setup):
   ```bash
   cd terraform/environments/k3s
   terraform init
   terraform apply   # requires the sudo setup from §0 above
   ```
   `terraform init` downloads the plugins Terraform needs (only required
   the first time, or after changing versions); `terraform apply` actually
   does the work, and will ask you to type `yes` to confirm before it
   makes any changes. If the cluster instead runs on a **separate**
   machine, follow `bootstrap/k3s-install.md` by hand on that machine
   instead.

   Either way, confirm it worked:
   ```bash
   kubectl get nodes                 # should show one node, STATUS = Ready
   kubectl get pods -n kube-system   # Traefik + local-path-provisioner should show Running
   ```
   ("Traefik" is the built-in traffic router that will later expose the
   app to your browser; "local-path-provisioner" is what gives the
   database somewhere to store its data on disk.)

2. **Install Argo CD + Sealed Secrets** — these are the two "robot" pieces
   everything else depends on: Argo CD watches this repo and deploys
   changes; Sealed Secrets lets passwords live safely in git.
   ```bash
   cd terraform/environments/bootstrap
   cp terraform.tfvars.example terraform.tfvars   # only edit this if your kubeconfig isn't at ~/.kube/config
   terraform init
   terraform apply
   ```
   Confirm:
   ```bash
   kubectl get pods -n argocd            # everything listed should say Running
   kubectl get pods -n sealed-secrets    # the controller pod should say Running
   ```
   This step can take a couple of minutes — Kubernetes has to download and
   start several container images the first time.

3. **Back up the Sealed Secrets private key.** When the Sealed Secrets
   controller first started in step 2, it generated an encryption key pair
   for itself. This key is the *only* thing that can decrypt every secret
   you're about to encrypt and commit — if you lose it, you can't get those
   secrets back, only regenerate new ones from scratch.
   ```bash
   kubectl get secret -n sealed-secrets \
     -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
     > ~/sealed-secrets-key-backup.yaml
   ```
   Written to your home directory on purpose, not this repo folder — this
   file is the *unencrypted* key itself (unlike a sealed secret), so it
   must never end up somewhere a `git add -A` could accidentally pick it
   up. (It's also listed in `.gitignore` as a backstop, in case it ever
   does land in this repo.) Move `~/sealed-secrets-key-backup.yaml`
   somewhere off this machine entirely — a password manager, an encrypted
   USB drive, anywhere that isn't this cluster — then delete the local
   copy once it's safely stored elsewhere.

4. **Generate each environment's secrets** (the actual database password,
   JWT signing key, etc., encrypted so they're safe to commit). Real values
   for these already live in `.env.local` as `DEV_POSTGRES_PASSWORD`/
   `DEV_JWT_SECRET`/`STAGING_POSTGRES_PASSWORD`/`STAGING_JWT_SECRET` (see
   that file's comment) — generate both sealed secrets from them with:
   ```bash
   ./scripts/generate-secrets.sh dev
   ./scripts/generate-secrets.sh staging
   ```
   (`scripts/bootstrap-cluster.sh` runs this step for you automatically —
   see the Shortcut note above.) The plaintext values never touch disk;
   only the encrypted result is written to
   `secrets/{dev,staging}/backend-secrets.sealed.yaml`. Commit those two
   files via a pull request, same as any other change to this repo. Prefer
   different real values per environment, and rotate them in `.env.local`
   (not by editing the `.sealed.yaml` files directly) if you ever need to
   change them — see `secrets/dev/README.md` for the manual `kubeseal`
   command this script wraps, if you'd rather not keep real values in
   `.env.local` at all.

5. **Sanity-check the Helm chart renders correctly** before handing it to
   Argo CD — this just generates the Kubernetes config files locally so you
   can catch a typo yourself instead of Argo CD failing on it later:
   ```bash
   helm lint charts/stock-hpp -f charts/stock-hpp/values.yaml -f charts/stock-hpp/values-dev.yaml
   helm template charts/stock-hpp -f charts/stock-hpp/values.yaml -f charts/stock-hpp/values-dev.yaml
   ```
   `helm lint` should end with something like `1 chart(s) linted, 0
   chart(s) failed`. `helm template` prints a large block of YAML to your
   screen — that's expected and fine; you're just confirming it doesn't
   error out.

6. **Tell Argo CD about the app** — this is the step where Argo CD learns
   "here's an app to watch and keep deployed":
   ```bash
   cd terraform/environments/dev
   cp terraform.tfvars.example terraform.tfvars
   terraform init && terraform apply

   cd ../staging
   cp terraform.tfvars.example terraform.tfvars
   terraform init && terraform apply
   ```

7. **Verify both Applications registered:**
   ```bash
   kubectl get applications -n argocd
   # stock-hpp-dev      Synced   Healthy
   # stock-hpp-staging  <may show OutOfSync until you do step 8 below — expected>
   ```

8. **Manually sync staging, once.** By design, staging doesn't deploy
   automatically — a human has to explicitly say "go" (this is a
   deliberate safety gate, explained more in §3):
   ```bash
   kubectl patch application stock-hpp-staging -n argocd --type merge \
     -p '{"operation":{"sync":{}}}'
   ```

9. **Confirm the app is actually running.** First, check that the
   one-time database-migration step completed and pods are up:
   ```bash
   kubectl get jobs -n stock-hpp-dev        # stock-hpp-backend-migrate should say Complete
   kubectl get pods -n stock-hpp-dev -o wide   # all pods should say Running
   ```
   Then check the backend directly. Its `/healthz` check isn't reachable
   through the website URL (only `/api` is routed to the backend there),
   so check it via a temporary tunnel instead:
   ```bash
   kubectl port-forward -n stock-hpp-dev svc/stock-hpp-backend 8000:8000 &
   curl http://localhost:8000/healthz   # should print: {"status":"ok"}
   kill %1   # closes the tunnel
   ```
   Finally, the real end-to-end check — the actual website, through the
   same route your browser would use:
   ```bash
   curl -I http://stock-hpp.dev.lan/
   # should print "HTTP/1.1 200 OK" as the first line
   ```
   (`stock-hpp.dev.lan` is a placeholder hostname from
   `charts/stock-hpp/values-dev.yaml` — it only resolves if you've pointed
   your machine's DNS/hosts file at it, or you're running `curl` from the
   cluster machine itself with that hostname mapped to `127.0.0.1`. If
   `curl` says it can't resolve the host, that's a DNS setup step outside
   this doc, not a sign anything above went wrong.)

🎉 **That's it — you now have a working Kubernetes cluster running the app
in a `dev` environment.** From here on, dev re-deploys automatically
whenever `values-dev.yaml`'s image tag changes in git; staging waits for an
explicit sync each time, same as step 8. The sections below cover what to
do next — read them as you need them.

---

## 2. Deploying a change

Once §0's one-time GitHub setup is done, this is fully automatic:

1. Merge the change in `stock-backend` or `stock-frontend`. Its CI builds,
   tests, and pushes the new image(s) to `ghcr.io`, then bumps the tag(s)
   in `charts/stock-hpp/values-dev.yaml` here and opens a PR
   (`bump-dev-backend`/`bump-dev-frontend`) — no action needed from you.
2. That PR auto-merges itself once this repo's required checks pass
   (usually within a minute or two).
3. Argo CD notices the change to `values-dev.yaml` and updates the cluster
   to match — running the database migration first, then rolling out the
   new version. You can force it to check immediately instead of waiting:
   ```bash
   kubectl patch application stock-hpp-dev -n argocd --type merge -p '{"operation":{"sync":{}}}'
   ```
4. Watch it happen:
   ```bash
   kubectl get application stock-hpp-dev -n argocd -w
   kubectl get jobs -n stock-hpp-dev
   kubectl get pods -n stock-hpp-dev -o wide
   ```

**Manual fallback** — if the bump job isn't set up yet (§0) or is
temporarily broken, do its job by hand:
```bash
git fetch origin && git merge --ff-only origin/main
git checkout -b bump-dev-<short-sha>
yq eval -i '.backend.image.tag = "<sha>"' charts/stock-hpp/values-dev.yaml
# if it was the backend that changed, also bump the db image tag alongside
# it — same commit, same image repo, they move together:
yq eval -i '.postgres.image.tag = "<sha>"' charts/stock-hpp/values-dev.yaml
# (use .frontend.image.tag instead if it was the frontend that changed —
# frontend has no matching second field)
git add charts/stock-hpp/values-dev.yaml
git commit -m "bump dev backend image to <sha>"
git push -u origin bump-dev-<short-sha>
gh pr create --fill
```

---

## 3. Promoting dev → staging

Staging is meant to be a deliberate, reviewed step — not something that
happens automatically the moment dev looks good. Two separate gates
protect that:

1. Every merge to `stock-backend`'s/`stock-frontend`'s `main` also opens a
   bump PR against `values-staging.yaml` here (`bump-staging-backend`/
   `bump-staging-frontend`), same as dev — but it does **not** auto-merge.
   Reviewing and merging that PR, whenever you decide dev looks good enough
   to promote, *is* the first gate. Each new push updates the same open PR
   in place rather than piling up a new one, so there's always at most one
   pending staging bump per app to look at. If the bump job isn't set up
   yet (§0), do the same edit by hand — see §2's manual fallback, targeting
   `values-staging.yaml` instead.
2. After merging, staging still does **not** deploy on its own — that's the
   second gate. Trigger it by hand once you're satisfied:
   ```bash
   kubectl patch application stock-hpp-staging -n argocd --type merge \
     -p '{"operation":{"sync":{}}}'
   ```
3. Confirm dev and staging are intentionally running different versions
   right now:
   ```bash
   kubectl get deploy -n stock-hpp-dev -o jsonpath='{.items[*].spec.template.spec.containers[0].image}'
   kubectl get deploy -n stock-hpp-staging -o jsonpath='{.items[*].spec.template.spec.containers[0].image}'
   ```

---

## 4. Rolling back a bad deploy

**Best option — undo it in git, let Argo CD catch up:**
```bash
git revert <bad-bump-commit-sha>   # on a new branch, PR, merge, same as any change
```
Argo CD notices the reverted file and rolls the cluster back to match —
automatically for dev, or via a manual sync (§3 step 2) for staging.

**Faster but temporary — roll back through Argo CD directly** (use only
when you can't wait for a git revert PR to land, e.g. something's actively
broken right now). Fix the underlying file in git afterward so the two
don't end up disagreeing:
```bash
argocd app history stock-hpp-dev
argocd app rollback stock-hpp-dev <history-id>
```
Dev automatically "heals" back to whatever `values-dev.yaml` says on its
next check-in — so this rollback gets undone again unless you also fix
`values-dev.yaml` in git. Treat it as a stopgap, not a fix.

**If the bad deploy is a broken database migration:** the app's old
version keeps running — Argo CD refuses to roll out the new one until the
migration step finishes successfully. Check what went wrong with:
```bash
kubectl logs -n stock-hpp-dev job/stock-hpp-backend-migrate
```

---

## 5. Rotating a secret (password, JWT key, etc.)

**Preferred:** edit the value in `.env.local`
(`DEV_POSTGRES_PASSWORD`/`DEV_JWT_SECRET`/`STAGING_POSTGRES_PASSWORD`/
`STAGING_JWT_SECRET`), then re-run:
```bash
./scripts/generate-secrets.sh <env>
```
This overwrites `secrets/<env>/backend-secrets.sealed.yaml` with a fresh
sealed secret built from the new value.

**By hand**, if you're not keeping real values in `.env.local`: the
command below takes the real password/secret as plain text on the command
line — most shells save that to your history file as-is. Fine for a
homelab, but worth knowing; clear it afterward with `history -d <line>` if
it bothers you, or prefix the command with a space (many shells, e.g. bash
with `HISTCONTROL=ignorespace`, skip logging space-prefixed lines).

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
Commit the result via a pull request, as usual. Once Argo CD syncs it, the
underlying secret updates — but **running pods don't automatically notice**
a secret changed (that's just how Kubernetes works), so after the sync,
restart them by hand:
```bash
kubectl rollout restart deployment -n stock-hpp-<env> stock-hpp-backend
```
If you're rotating `POSTGRES_PASSWORD` specifically, changing the secret
alone isn't enough — the database itself needs to be told its password
changed too (`kubectl exec` into the postgres pod and run `ALTER USER
stock_hpp_user WITH PASSWORD '...'`). Do that *first*, then update the
sealed secret — otherwise there's a window where the backend's new
password doesn't match what the database actually has.

---

## 6. Scaling up (running more copies of the app)

How many copies ("replicas") of the backend/frontend run is set in
`values.yaml` (`backend.replicaCount`, `frontend.replicaCount`). To change
it for one environment only, add the override to that environment's
`values-<env>.yaml` file rather than editing the shared default, then PR
it as usual. The database is intentionally always a single copy — see
`docs/adr/0002-gitops-deployment-architecture.md` for why that's a real
limit of this setup, not something you can fix by just bumping a number.

---

## 7. Troubleshooting

| What you're seeing | Likely cause | How to check |
|---|---|---|
| Argo CD Application stuck `OutOfSync`/`Progressing` | The database migration step failed or hasn't finished | `kubectl get jobs -n stock-hpp-<env>`, `kubectl logs job/stock-hpp-backend-migrate -n stock-hpp-<env>` |
| Argo CD Application shows `Unknown`/`Degraded` | The Helm chart failed to render, or a values file has an error | Run the `helm template` command from §1 step 5 locally to reproduce; `kubectl describe application <name> -n argocd` for details |
| Pods stuck `ImagePullBackOff` | The image tag in `values-<env>.yaml` doesn't exist on `ghcr.io` yet | `kubectl describe pod <pod-name> -n stock-hpp-<env>`; confirm the tag was actually pushed by `stock-backend`/`stock-frontend`'s CI |
| Backend pods `CrashLoopBackOff` | Wrong `DATABASE_URL`/`JWT_SECRET` in the sealed secret, or the database isn't ready yet | `kubectl logs -n stock-hpp-<env> deploy/stock-hpp-backend` |
| Website returns 502/504 | The backend or frontend has no healthy pods to send traffic to | `kubectl get endpoints -n stock-hpp-<env>` |
| `kubeseal` command fails | Not pointed at the right cluster, or the Sealed Secrets controller isn't running | `kubectl get pods -n sealed-secrets`; `kubeseal --fetch-cert` to test the connection |
| `terraform apply` in `dev`/`staging` fails mentioning a missing CRD/type for "Application" | `terraform/environments/bootstrap` (which installs Argo CD) wasn't applied yet, or isn't finished starting up | `kubectl get pods -n argocd` — all should say Running, then retry |
| Browser shows a CORS error in the console | `CORS_ORIGINS` in `values-<env>.yaml` doesn't match the actual website address | Compare `backend.env.CORS_ORIGINS` and `ingress.host` in that environment's values file |
| `terraform apply` in `environments/bootstrap` errors mentioning "timed out waiting for the condition" (redis, server, etc.) | Not a real failure — a first-time Argo CD install has to pull ~7 images with nothing cached, which can take longer than the configured wait timeout; Kubernetes keeps going in the background regardless of whether Terraform is still watching | `kubectl get pods -n argocd` — if everything's `1/1 Running`, you're fine; re-run `terraform apply`, it'll show "No changes" since the install already succeeded |
| `scripts/bootstrap-cluster.sh` says "waiting for pods in argocd to be Ready" and times out even though `kubectl get pods -n argocd` shows everything `1/1 Running` | Argo CD's chart includes a one-shot Job (`argocd-redis-secret-init`); once its pod completes, Kubernetes marks it `Ready=False` permanently (it's done, not pending) — an unfiltered wait for "all pods Ready" waits forever for a pod that will never be Ready again | Already fixed in the script (excludes completed pods from the wait) — if you're on an older copy, `git pull`/re-copy the script, or just `kubectl get pods -n argocd` yourself and move on if everything real is Running |
| `terraform apply` in `environments/k3s` fails immediately mentioning sudo/password | The passwordless-sudo setup from §0 wasn't done, or was typed slightly wrong | `sudo -n -l \| grep k3s-install.sh` — should print a line listing all 3 commands; redo the §0 steps if empty |
| `terraform destroy` in `environments/k3s` hangs or fails mentioning sudo/password | Same setup, but specifically missing the uninstall permission | `sudo -n -l \| grep k3s-uninstall.sh` — should print the same line as above; redo the §0 steps if empty |
| **On WSL2 with Docker Desktop:** k3s never becomes Ready — `systemctl status k3s` shows `activating (auto-restart)`, journal says `Failed to start ContainerManager... system validation failed - wrong number of fields (expected 6, got 7)` | Docker Desktop's WSL integration mounts a share whose options string contains an unescaped space (`C:\Program Files\Docker\...`); kubelet's mount-table parser expects exactly 6 fields per line and chokes on the extra one from that space. Known upstream bug: [k3s-io/k3s#4483](https://github.com/k3s-io/k3s/issues/4483) — not something a longer timeout fixes | `grep "Program Files" /proc/mounts` confirms it. Fix (Windows side, not fixable from inside WSL): Docker Desktop → Settings → Resources → WSL Integration → turn **off** the toggle for this distro, then `wsl --shutdown` from PowerShell and reopen. The k3s install itself doesn't need re-running — `terraform state` already has it; just re-run `bootstrap-cluster.sh` afterward and the node-Ready wait will succeed once the service is actually healthy |

---

## 8. Things that aren't solved yet (know these before you rely on this)

- **The database has no backup.** It's a single copy storing its files on
  this machine's disk — if that disk fails, the data is gone. This is a
  real gap, not an oversight left for later reading: if you're going to
  put real data in here, back up the database yourself (e.g. a scheduled
  `pg_dump`) until this gets built properly.
- **Terraform's own state files live only on this machine**
  (`terraform/environments/*/backend.tf` explains why). If this machine is
  lost, Terraform "forgets" what it already set up — the cluster itself
  keeps running fine, but a future `terraform apply` from a fresh checkout
  would try to create everything again from scratch and collide with what
  already exists. Back up the `terraform.tfstate` files alongside the
  Sealed Secrets key (§1 step 3) if this matters to you.
- **Rebuilding from nothing** = redo §1 top to bottom, or
  `./scripts/bootstrap-cluster.sh` again (it's safe to re-run — each stage
  is a no-op if nothing changed, same as running `terraform apply` twice
  in a row). Everything about *how the app is configured* comes back
  automatically from git once Argo CD is pointed at this repo again — it's
  only the database's actual data and the Sealed Secrets private key that
  don't come back on their own. To tear everything down cleanly first
  (e.g. before rebuilding from scratch to test the whole flow again):
  ```bash
  ./scripts/destroy-cluster.sh
  ```
  Mirrors `bootstrap-cluster.sh` in reverse (`staging` → `dev` →
  `bootstrap` → `k3s`), asks you to type `DESTROY` to confirm, and cleans
  up the now-stale `~/.kube/config` afterward automatically. `--keep-k3s`
  tears down just the app layer and leaves k3s running, if you want to
  re-test `bootstrap-cluster.sh` without waiting through a fresh k3s
  install + image pulls again.

---

## 9. Adding a new environment (e.g. production)

1. Copy `charts/stock-hpp/values-staging.yaml` → `values-production.yaml`,
   and adjust the image tags/hostname/CORS setting inside it.
2. Copy `terraform/environments/staging/` →
   `terraform/environments/production/`, and update the app name,
   destination namespace, values files, and secrets path throughout to say
   "production" instead of "staging".
3. `mkdir secrets/production`, then generate its sealed secret following
   §5 above.
4. `cd terraform/environments/production && terraform init && terraform apply`.
5. Decide deliberately whether production auto-deploys or needs a manual
   sync like staging — don't just copy staging's choice without thinking
   about it.

---

## Glossary

Quick definitions for terms used above without much explanation, in case
you land on a section out of order:

- **Pod** — the smallest running unit in Kubernetes; usually one running
  copy of a container (e.g. one copy of the backend).
- **Deployment** — a Kubernetes object that manages a set of identical
  Pods, keeping the right number running and rolling out updates.
- **Job** — a Kubernetes object for a task that runs once to completion,
  rather than staying up (used here for the database migration).
- **Service** — a stable network address that routes to whichever Pods are
  currently healthy for a given app.
- **Ingress** — the config that maps an external hostname/path (like
  `stock-hpp.dev.lan/api`) to an internal Service.
- **ConfigMap / Secret** — Kubernetes objects holding configuration values;
  a Secret is for sensitive values (passwords, keys), a ConfigMap for
  everything else.
- **StatefulSet** — like a Deployment, but for things that need stable
  identity/storage, like a database.
- **PVC (PersistentVolumeClaim)** — a request for a chunk of disk storage
  that survives even if the Pod using it restarts.
- **CRD (Custom Resource Definition)** — how Kubernetes lets a tool (like
  Argo CD) add its own new object types, like "Application", on top of the
  built-in ones.
- **Sync** — Argo CD's term for "make the cluster match what git says right
  now."
- **Rollout** — the process of replacing old Pods with new ones when a
  Deployment changes.

---

## Quick reference

```bash
# Full first-time bootstrap (see §1) — preview only, changes nothing
./scripts/bootstrap-cluster.sh --plan-only

# Full teardown, reverse order — preview only, changes nothing
./scripts/destroy-cluster.sh --plan-only

# Namespaces / Applications
kubectl get applications -n argocd
kubectl get pods -n stock-hpp-dev -o wide
kubectl get pods -n stock-hpp-staging -o wide

# Force a sync
kubectl patch application stock-hpp-<env> -n argocd --type merge -p '{"operation":{"sync":{}}}'

# Migration Job status/logs
kubectl get jobs -n stock-hpp-<env>
kubectl logs -n stock-hpp-<env> job/stock-hpp-backend-migrate

# Current running image per environment
kubectl get deploy -n stock-hpp-<env> -o jsonpath='{.items[*].spec.template.spec.containers[0].image}'

# Terraform, per layer
cd terraform/environments/{k3s,bootstrap,dev,staging} && terraform plan
```
