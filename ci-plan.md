# CI plan

What `.github/workflows/ci.yml` checks, and why it's shaped the way it is. This
repo is IaC (Terraform + a Helm chart + shell scripts), not application code, so
its CI is a lint/validate/scan suite rather than a build-test-deploy pipeline —
there's no Dockerfile or app image here to build or push.

## Why Terraform CI is validate-only

Every environment under `terraform/environments/` (`k3s`, `bootstrap`, `dev`,
`staging`) uses **local state** (`backend "local"`), and the actual deploy
target is a homelab k3s cluster that hosted GitHub Actions runners can't reach.
That means CI can never legitimately `plan` or `apply` — there's no shared
state to plan against and no cluster to apply to. CI is deliberately scoped to
what's checkable without either of those: formatting (`terraform fmt -check`)
and config validity (`terraform init -backend=false` + `terraform validate`,
which only needs provider schemas, not real state). Applying changes stays a
human running `scripts/bootstrap-cluster.sh` (or the underlying `terraform
apply`) by hand, per `runbook.md`.

## Jobs

| Job | What it checks |
|---|---|
| `secret-scan` | gitleaks over full history — catches committed credentials, including accidental plaintext leaking into `secrets/*.sealed.yaml` (should only ever be ciphertext) or `terraform/**/terraform.tfvars` (gitignored, but worth a belt-and-suspenders history scan). |
| `terraform-fmt` | `terraform fmt -check -recursive`, run once for the whole `terraform/` tree. |
| `terraform-validate` | `terraform validate` per environment (matrix over `k3s`/`bootstrap`/`dev`/`staging`), `init -backend=false` and no `-upgrade` — so it validates against the exact provider versions pinned in each `.terraform.lock.hcl`, and a `versions.tf` bump without a matching lock-file update fails loudly instead of drifting. |
| `helm` | `helm lint` + `helm template`, per values overlay (`dev`, `staging`), against `charts/stock-hpp` — the same manual pre-Argo-CD sanity check `terraform/README.md` already documents, now automated. Helm is pinned to v3.21.4 explicitly: the chart's `apiVersion: v2` and the `hashicorp/helm` Terraform provider both require Helm v3, so CI shouldn't silently pick up a future v4 default. |
| `shellcheck` | `scripts/*.sh` at `severity: warning` (stricter than default) — these scripts mutate a live cluster (`bootstrap-cluster.sh`, `destroy-cluster.sh`) and `generate-secrets.sh` handles secret material, so the bar is intentionally tight. |
| `dependency-review` | PR-only. No supported manifest exists in this repo today (no `package.json`/`requirements.txt`/etc.), so this is currently a no-op — kept for parity with the sibling `stock-*` repos' CI shape and so it activates automatically if such a manifest is ever added. |
| `iac-scan` | Trivy config-mode scan, run separately against `terraform/` and `charts/` (two SARIF uploads, distinct Security-tab categories) at `HIGH,CRITICAL` severity — the IaC analog of the image vulnerability scan the app repos run against their container builds. |
| `sonarcloud` | Static analysis over `terraform/`, `charts/`, `scripts/` (see `sonar-project.properties`); gated on `terraform-validate` + `helm` + `shellcheck` passing, since there's no single `test` job here to key off the way the app repos do. |

## Manual prerequisites

These aren't things a code change can do — they're GitHub/SonarCloud settings:

1. A `SONAR_TOKEN` repo secret (Settings → Secrets and variables → Actions).
2. The `theadonata_stock-infrastructure` project must exist and be linked
   under the `theadonata` SonarCloud org before the `sonarcloud` job can pass.
3. To make these checks actually gate merges (not just report), add the job
   names above to `main`'s required-status-checks list in branch protection
   settings.

## Out of scope here

- The `bump-dev`/`bump-staging` image-tag-promotion jobs described in
  `gitops-plan.md` belong in `stock-backend`'s and `stock-frontend`'s own
  `ci.yml` (they check out this repo and bump `values-dev.yaml`/
  `values-staging.yaml`), not here.
- Structural validation of `secrets/*.sealed.yaml` (confirming well-formed
  `SealedSecret` YAML, not decrypting anything) is a plausible cheap future
  addition, not part of this workflow yet.
