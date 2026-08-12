# stock-infrastructure

CI/CD, deployment, and IaC for the Stock/HPP business-finance project.

Part of the `stock-*` multi-repo project. See CLAUDE.md for scope and
sibling-repo relationships.

## Purpose

This repo will own CI/CD and deployment for the project: eventually,
Kubernetes manifests (Deployments, Services, Ingress, ConfigMaps/Secrets)
targeting a self-hosted k8s cluster on a VPS, per the design spec. It wires
together the independently-built `stock-backend` and `stock-frontend`
container images by referencing them by tag — it does not read or depend on
either repo's source directly.

## Current status

Not yet implemented — no cloud provider, IaC tool, or CI/CD platform has
been chosen, and no infra code exists yet (see CLAUDE.md). Kubernetes
manifests are a follow-up task, tracked in `stock-business-analyst`'s
`questions.md`.

In the meantime, `stock-backend` and `stock-frontend` each own their own
`Dockerfile` and `docker-compose.yml` for local development, independent of
this repo. Once scoped, `stock-infrastructure` will build on top of those
per-repo Docker images and deploy them via k8s manifests (plus an Ingress
controller for HTTPS/routing), rather than replacing them.

## Design reference

See `stock-business-analyst/docs/superpowers/specs/2026-08-12-stack-architecture-design.md`
for the full stack/architecture design, including the intended
infrastructure approach.

See `infrastructure.md` (this repo) for a Kubernetes deployability and
scalability assessment of the current architecture — what's already
k8s-ready, concrete blockers to fix first (migration execution, missing
readiness probe, frontend's build-time backend URL), and open decisions
(cloud/VPS + k8s distribution, Postgres hosting) tracked in
`stock-business-analyst/questions.md`.
