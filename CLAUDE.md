# CLAUDE.md

This is the **infrastructure** repo for the Stock/HPP business-finance project.

## Project status

No cloud provider, IaC tool, or CI/CD platform has been chosen yet and no
infra code exists. Don't assume one — ask the user before scaffolding
anything.

## Relationship to sibling repos

This project is split across independent repos, each buildable and
deployable on its own with no shared code or path dependency between them:

- `stock-frontend` — client-side UI
- `stock-backend` — API / business logic / data layer
- `stock-infrastructure` (this repo) — CI/CD, deployment, IaC
- `stock-qa` — test plans, test automation
- `stock-business-analyst` — requirements, specs, source material (incl. the original HPP/business-finance notes)

This repo provisions/deploys the others; it should reference them by
published artifact or deploy target (container image, build output), never
by reading their source directly.

## Working here

`.claude/` config (agents, hooks, skills, MCP) is kept identical across all
five repos on purpose, so any agent persona works the same way regardless of
which repo it's invoked in. Once a target platform is chosen, update this
file with real commands and architecture notes.
