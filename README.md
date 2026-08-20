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

**Known gap:** the `bump-dev`/`bump-staging` CI jobs that automate image
promotion now exist in `stock-backend`'s/`stock-frontend`'s
`.github/workflows/ci.yml`, but depend on one-time GitHub account/repo
setup (a PAT, a secret, two settings toggles) that hasn't been done yet —
see `runbook.md` §0 "Enabling automatic image promotion". Until then, image
promotion falls back to the manual PR flow documented in `runbook.md` §2.

`stock-backend` and `stock-frontend` each still own their own `Dockerfile`
and `docker-compose.yml` for local development, independent of this repo —
this repo builds on top of those images rather than replacing them.

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
  bootstrap's `terraform apply` steps in order (`k3s` → `bootstrap` →
  `dev` → `staging`) instead of doing each one by hand; see `runbook.md`
  §1. Supports `--plan-only` for a dry run.
- `scripts/destroy-cluster.sh` — the reverse: `terraform destroy` in order
  (`staging` → `dev` → `bootstrap` → `k3s`), with a "type DESTROY to
  confirm" gate. `--keep-k3s` tears down just the app layer (useful for
  re-testing bootstrap without reinstalling k3s); `--plan-only` previews
  with no changes.
- `scripts/generate-secrets.sh {dev,staging}` — builds
  `secrets/<env>/backend-secrets.sealed.yaml` from real values in
  `.env.local`, run automatically by `bootstrap-cluster.sh` for whichever
  environment doesn't already have one.
- `docs/adr/` — architecture decision records: tool choices and why
  (`0002-gitops-deployment-architecture.md`), the cross-repo bump
  credential (`0001-cross-repo-bump-credential.md`).
- `terraform/` — Terraform modules/environments that provision k3s itself,
  Argo CD, Sealed Secrets, namespaces, and the per-environment Argo CD
  Applications.
- `charts/stock-hpp/` — the umbrella Helm chart Argo CD renders and syncs.
- `secrets/` — per-environment `SealedSecret` manifests (encrypted, safe to
  commit); see `secrets/dev/README.md` for how to generate them.
