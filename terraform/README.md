# Terraform layout

Applies `../gitops-plan.md`'s design with Terraform managing everything from
k3s itself down through the cluster internals (Argo CD, Sealed Secrets,
namespaces, Argo CD Applications).

```
terraform/
├── modules/
│   ├── k3s/                    # installs k3s on the local machine (local-exec)
│   ├── namespace/            # generic kubernetes_namespace, reused by dev/staging
│   ├── argocd/                # installs Argo CD (helm_release)
│   ├── sealed-secrets/         # installs the Sealed Secrets controller (helm_release)
│   └── argocd-application/     # generic multi-source Argo CD Application CR,
│                                # parameterized per environment
└── environments/
    ├── k3s/          # Phase -1 — installs k3s, applied once, before bootstrap
    ├── bootstrap/    # Phase 0 — cluster-wide, applied once, before dev/staging
    ├── dev/          # Phase 1 — namespace + automated-sync Application
    └── staging/      # Phase 2 — namespace + manual-sync Application
```

Each `environments/<env>/` is its own Terraform root module with its own
state (`backend.tf`, local state — see that file for why) — they are applied
independently, in this order:

## 0. k3s (once — only if the cluster runs on this same machine)

```bash
cd environments/k3s
terraform init
terraform apply
```

Installs k3s directly on the machine you're running Terraform from, via a
`local-exec` provisioner (`terraform/modules/k3s`) — there's no official k3s
Terraform provider, so this is the one place in this repo that shells out
instead of using a real provider resource. **Requires passwordless sudo**
for three specific commands: `local-exec` has no interactive TTY, so a real
sudo password prompt would just hang until Terraform's operation times out.
`terraform/modules/k3s` is written specifically so the sudoers rule can name
exact commands instead of a wildcard like `sh -c *` (which would be
unrestricted passwordless root, not a scoped exception) — the installer
runs from a fixed, version-baked-in script at
`$HOME/.cache/k3s-install.sh` (not `/tmp`, which is world-writable and would
let another local user race/replace the script before sudo runs it) with no
extra arguments, so the rule can match that literal path:

```bash
cat <<EOF | sudo tee /etc/sudoers.d/k3s-terraform
$(whoami) ALL=(root) NOPASSWD: /usr/bin/sh $HOME/.cache/k3s-install.sh, /usr/bin/cat /etc/rancher/k3s/k3s.yaml, /usr/local/bin/k3s-uninstall.sh
EOF
sudo chmod 440 /etc/sudoers.d/k3s-terraform
sudo visudo -c   # validates syntax before it takes effect
```

Confirm it took — grep for `k3s-uninstall.sh` specifically (not
`k3s-terraform`, which is only the sudoers *file's name* and never appears
in `sudo -l`'s own output), since that's the command
`terraform destroy` in `environments/k3s` depends on to run
non-interactively:

```bash
sudo -n -l | grep k3s-uninstall.sh
```

(This is still real passwordless root access to exactly these three
commands — reasonable to accept on a single-operator homelab box, but worth
being deliberate about, not something to copy onto a shared machine without
thinking it through. If the cluster instead runs on a **separate** box,
skip this whole section and follow `../bootstrap/k3s-install.md` by hand on
that box instead — this module only applies to the same-machine case.)

`terraform destroy -target=module.k3s` (from this directory) runs k3s's own
uninstaller, so this is reversible.

## 1. Bootstrap (once)

```bash
cd environments/bootstrap
cp terraform.tfvars.example terraform.tfvars   # adjust kubeconfig_path if needed
terraform init
terraform apply
```

Installs Argo CD and the Sealed Secrets controller into the cluster. The
Sealed Secrets controller generates its own keypair on first run — back up
the private key material outside the cluster by hand
(`kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key`),
Terraform doesn't manage that key.

After this, generate each environment's `backend-secrets.sealed.yaml` —
either `../scripts/generate-secrets.sh {dev,staging}` (reads real values
from `../.env.local`) or by hand per `../secrets/dev/README.md` — and
commit them. Terraform does not create these itself; they're opaque,
environment-specific ciphertext with nothing to template (see
`../gitops-plan.md`'s tool-selection table).

Also sanity-check the chart independently of Argo CD before relying on it:

```bash
helm lint ../charts/stock-hpp -f ../charts/stock-hpp/values.yaml -f ../charts/stock-hpp/values-dev.yaml
helm template ../charts/stock-hpp -f ../charts/stock-hpp/values.yaml -f ../charts/stock-hpp/values-dev.yaml
```

## 2. Dev (Phase 1, fully automated after this)

```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Creates the `stock-hpp-dev` namespace and an Argo CD Application with
`syncPolicy.automated {prune, selfHeal}` — from here on, every commit to
`values-dev.yaml` (via CI's `bump-dev` job) rolls out with no further
Terraform runs needed. Re-run `terraform apply` here only if the
Application's own definition changes (e.g. a new values file, a different
target revision).

## 3. Staging (Phase 2, human-gated)

```bash
cd environments/staging
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Same shape, but `automated_sync = false` — staging requires an explicit
`Sync` (Argo CD UI or `argocd app sync stock-hpp-staging`) after each
promotion PR is merged by hand. This is the deliberate environment-promotion
gate described in `../gitops-plan.md` Phase 2, on top of the PR-merge gate.

## Why Terraform here, and why split this way

The original plan (`../gitops-plan.md`) had Phase 0 as a sequence of
`kubectl apply -f` commands and `argocd-apps/<env>-app.yaml` as hand-written
manifests. This replaces both with Terraform so the whole bootstrap +
Application-registration layer is declarative, diffable (`terraform plan`),
and re-runnable — while leaving the actual application deployment
(Deployments, Services, the migration Job, Postgres) exactly where the plan
put it: inside `../charts/stock-hpp`, rendered and reconciled continuously by
Argo CD, not by Terraform. Terraform's job stops at "Argo CD knows this
Application exists and where to sync it from" — everything after that commit
is GitOps, not further `terraform apply` runs. That boundary is also why
`environments/dev` and `environments/staging` use the `kubectl_manifest`
resource (via the `gavinbunney/kubectl` provider) for the Application CR
instead of Terraform's own `kubernetes_manifest`: the latter needs the
Application CRD's schema already registered in the cluster at *plan* time,
which only holds here because `environments/bootstrap` — installing Argo CD,
which registers that CRD — is a separate, earlier `terraform apply`.

## Provider versions

Pinned chart versions (`argocd_chart_version`, `sealed_secrets_chart_version`
in `environments/bootstrap/variables.tf`) and provider version constraints
(`~>` in each environment's `versions.tf`) are deliberately pinned rather
than left floating, consistent with a solo-operator homelab where nothing
else re-validates a surprise upgrade. Bump them by hand after checking
release notes, not automatically.

**Checked against live upstream (2026-08-19):**

| Pin | Value | Latest available | Status |
|---|---|---|---|
| k3s (`environments/k3s`) | v1.36.3+k3s1 | v1.36.3+k3s1 (`stable` channel) | current |
| `argo-cd` chart | 10.4.0 | 10.4.0 | current |
| `sealed-secrets` chart | 2.19.2 | 2.19.2 | current |
| `hashicorp/kubernetes` provider | `~> 2.31` → 2.38.0 | **3.2.1** | intentionally behind — see below |
| `hashicorp/helm` provider | `~> 2.14` → 2.17.0 | **3.2.0** | intentionally behind — see below |
| `hashicorp/null` provider | `~> 3.2` → 3.3.1 | 3.3.1 | current |
| `gavinbunney/kubectl` provider | `~> 1.14` → 1.19.0 | 1.19.0, but no release since Jan 2025 | current version, project looks unmaintained |

**`hashicorp/kubernetes` and `hashicorp/helm` are deliberately capped below
their v3 majors.** Both v3 releases ship an upgrade guide (breaking
changes), and this repo's resources — `kubernetes_namespace`, `helm_release`
with attributes like `render_subchart_notes`/`wait_for_jobs` — were written
and validated (`terraform validate`/`plan`, see the rest of this doc)
against the 2.x schema. Bumping to `~> 3.0` needs its own pass reading both
upgrade guides and re-validating every module, not a one-line constraint
edit — hasn't been done yet.

**`gavinbunney/kubectl`** (used only by `modules/argocd-application`) is at
its own latest release, but that project hasn't shipped since January
2025. If it stops working against a future Kubernetes version, an actively
maintained fork exists: `alekc/terraform-provider-kubectl`. Not an issue
today — noted for whoever hits it first.

**The `helm` CLI installed locally for `helm lint`/`helm template` sanity
checks (§1 in `../runbook.md`) is deliberately kept on v3** (Helm v4 is now
the current major upstream) — it needs to match what actually renders this
chart in practice: the `hashicorp/helm` *provider* pin above still uses
Helm's v3 SDK internally, and this chart's `Chart.yaml` targets the Helm v3
schema (`apiVersion: v2`). Installing the v4 CLI locally would risk `helm
lint`/`helm template` passing or failing differently than what Argo CD and
Terraform actually do — revisit together with the provider v3 bump above,
not separately.
