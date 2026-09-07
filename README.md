# stock-infrastructure

> Deploys and runs the Stock/HPP app on a server.

## About the project

**Stock/HPP** is a small web app that replaces an Excel spreadsheet for
tracking a small business's sales, stock, expenses, and cost of goods
sold. The app itself lives in two other repos
([stock-backend](https://github.com/theadonata/stock-backend) and
[stock-frontend](https://github.com/theadonata/stock-frontend)) — this
repo is what actually runs them on a real server and keeps them running.

It owns three things: **CI/CD** (getting a code change from those repos
into production automatically), **deployment** (what's actually running,
and where), and **infrastructure as code** (the server setup itself,
defined in files instead of clicked together by hand).

### Part of a bigger project

Stock/HPP is split into six repos, each one buildable and deployable on
its own:

| Repo | What it does |
|---|---|
| [stock-frontend](https://github.com/theadonata/stock-frontend) | The web app people use day to day |
| [stock-backend](https://github.com/theadonata/stock-backend) | The API and database — stores data, does the math |
| **stock-infrastructure** (this repo) | Deploys and runs everything on a server |
| [stock-qa](https://github.com/theadonata/stock-qa) | Automated tests that check everything works |
| [stock-business-analyst](https://github.com/theadonata/stock-business-analyst) | The original business requirements this is built from |
| [stock-platform](https://github.com/theadonata/stock-platform) | An internal dashboard for the team building this project |

This repo only ever refers to the app repos by their built container
image — it never reads their source code directly.

## How it works, in plain terms

The app runs on a small home Kubernetes cluster ([k3s](https://k3s.io/)).
Getting a code change live works like this:

1. Someone merges a change to `stock-backend` or `stock-frontend`. That
   repo's own CI builds a new container image and automatically opens a
   pull request here, updating a config file to point at it.
2. That pull request merges on its own for the **dev** environment — dev
   always runs the latest code.
3. For **staging**, the same pull request merges automatically too, but a
   person has to explicitly click "sync" before it actually goes live —
   one deliberate checkpoint before anything more permanent.
4. [Argo CD](https://argo-cd.readthedocs.io/) is the piece watching this
   repo and making the live cluster match whatever it currently says —
   this pattern is called **GitOps**: git is the source of truth, not a
   person manually running deploy commands.

Alongside the app, this repo also runs a shared monitoring stack
(Prometheus for metrics, Grafana for dashboards, Loki for logs), which
posts alerts to Discord when something needs attention.

[Terraform](https://www.terraform.io/) (via
[Terragrunt](https://terragrunt.gruntwork.io/)) is what sets all of this
up in the first place — the cluster itself, Argo CD, and the secrets
manager — but stops there. Once that scaffolding exists, everyday changes
flow through git + Argo CD, not more Terraform runs.

## Built with

- [k3s](https://k3s.io/) — a lightweight Kubernetes distribution
- [Argo CD](https://argo-cd.readthedocs.io/) — keeps the cluster in sync
  with this repo (GitOps)
- [Helm](https://helm.sh/) — packages the app as a chart Argo CD can deploy
- [Terraform](https://www.terraform.io/) + [Terragrunt](https://terragrunt.gruntwork.io/) — sets up the cluster and its core tools
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) —
  encrypts secrets so they're safe to commit to this repo
- Prometheus + Grafana + Loki + Alertmanager — metrics, dashboards, logs,
  and alerts

## Getting started

**[`runbook.md`](./runbook.md) is the real getting-started guide** — a
step-by-step walkthrough for first-time setup, deploying a change,
promoting dev → staging, rolling back, rotating secrets, and
troubleshooting. Start there for anything hands-on.

### Prerequisites

- Terraform, Terragrunt, `kubectl`, and Helm installed
- A machine to run k3s on (this can be the same machine you run Terraform
  from)

### First-time setup

```bash
./scripts/bootstrap-cluster.sh
```

Runs the full first-time setup in order. Add `--plan-only` to preview
without changing anything. See `runbook.md` §1 for the full walkthrough,
including one-time account setup this depends on.

### Tearing it down

```bash
./scripts/destroy-cluster.sh
```

The reverse, with a confirmation prompt before it does anything. See
`runbook.md` for the safer partial options (e.g. `--keep-k3s`).

## Project structure

```
terraform/     provisions the cluster and its core tools
charts/        the Helm charts Argo CD actually deploys
scripts/       setup/teardown/secret-generation helper scripts
secrets/       encrypted secrets (safe to commit — see Sealed Secrets above)
docs/adr/      architecture decisions and why they were made
runbook.md     the step-by-step operational guide — start here
spikes/        small, disposable research experiments (see each spike's use-case.md)
```

## Learn more

- [`runbook.md`](./runbook.md) — the operational guide, for anything
  hands-on
- [`docs/adr/0002-gitops-deployment-architecture.md`](./docs/adr/0002-gitops-deployment-architecture.md) —
  the core architecture decision; start here for the "why" behind the setup above
- [`docs/adr/`](./docs/adr/) — every other architecture decision made in
  this repo, including a proposed (not yet built) AWS-based setup for
  production/disaster-recovery
