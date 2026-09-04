# CLAUDE.md

This is the **infrastructure** repo for the Stock/HPP business-finance project.

## Project status

IaC is Terraform + Terragrunt (see `terraform/README.md`), CI/CD is GitHub
Actions, and the cloud provider is AWS (production/DR — ADR 0004), validated
against the Floci emulator before any real spend. The homelab tier (dev/
staging/monitoring) runs on k3s. Don't re-litigate these choices or ask the
user which platform to use — they're already decided; see `terraform/README.md`
and `docs/adr/` for the how and why.

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

## Skill Activation

At the start of any task-oriented session — any interaction where you will
use tools and produce deliverables — invoke the task-observer skill before
beginning work. This ensures skill improvement opportunities are captured
throughout the session.

When loading any skill, check the observation log for OPEN observations
tagged to that skill. Apply their insights to the current work, even if
the skill file hasn't been updated yet. This enables immediate application
of observations before they're permanently integrated during the weekly
review.

## Git

Commit, push, and open a PR automatically as part of completing a task —
this is standing authorization across all five `stock-*` repos, no need to
ask first each time. Use atomic-commit (or equivalent judgment) to split
work into logical commits, then push the branch and open the PR without
waiting for a separate go-ahead.

Never push directly to the `main` branch, even when explicitly asked to
"push" or "commit and push" — `main` is protected and requires a pull
request. Always push to a new branch and open a PR instead, across all
five `stock-*` repos.

Always branch off `main` for new work, and sync first: run
`git fetch origin && git merge --ff-only origin/main` (or
`git pull --ff-only`) before creating the branch — cutting a branch from a
stale local `main` produces a PR with a stale diff or spurious merge
conflicts.

## Jira

When picking up a Jira ticket (e.g. `STOCK-*`), always post the resulting
GitHub PR URL back to that ticket once the PR is open — don't leave the
Jira card without a pointer to the PR that implements it.

- Always set the **`GitHub Pull Request` field** (`customfield_10046`, a
  plain short-text field on the STOCK project) to the PR URL —
  `editJiraIssue` with `fields: {"customfield_10046": "<url>"}` sets it
  directly; no Jira UI step needed for this (only *creating*/attaching a
  new custom field to an issue type's layout needs a human — this field
  already exists and is already attached, confirmed 2026-09-04). If an
  issue picks up more than one PR over time, list every URL in the field
  (comma-separated) rather than overwriting with just the latest.
- Also add a plain comment with the PR link and a short summary of what
  it does — the field is a quick-glance pointer, the comment is the
  narrated history of what happened and why. Do both, not one or the
  other.
- If a ticket's issue type somehow lacks this field (verify with
  `getJiraIssue` + `expand: "editmeta"` before assuming it doesn't), fall
  back to a comment only and don't block the update on getting the field
  added first.

## Terraform module structure

Always separate Terraform modules by infrastructure component — one
`terraform/modules/<component>/` per component (e.g. `vpc`, `eks`, `iam`,
`security-group`, `k3s`, `argocd`, `namespace`), never several unrelated
components' resources sharing one module because they happened to land in
the same ticket. This applies from the start of a new piece of Terragrunt
work, not just as a later cleanup: when a ticket needs a new AWS resource
family (an IAM role, a security group, an RDS/Aurora cluster, an ALB,
etc.), give it its own `modules/<component>/` up front rather than adding
it into an existing module (e.g. don't grow `modules/eks` to also hold a
security group `modules/eks` doesn't otherwise own) — component modules
can still depend on each other's outputs (an `eks` module consuming a
`security-group` module's ID, say) without merging into one file. A
`*-environment` root module (what Terragrunt's `terraform.source` actually
points at, e.g. `modules/aws-environment`) should only instantiate
component modules and wire their inputs/outputs together — it holds no
`resource`/`data` blocks of its own. See `terraform/README.md`'s "Module
structure" section for the full rationale and the precedent (`vpc.tf`/
`eks.tf` briefly lived inline in `modules/aws-environment` before being
split into `modules/vpc`/`modules/eks`).

When splitting an existing inline resource out into its own module (or
adding a new component), add `moved` blocks (see
`terraform/modules/aws-environment/moved.tf` for the pattern) so
`terragrunt plan` shows zero diff against any already-applied environment
— don't rely on `terraform state mv` run by hand, and don't skip this step
because "nothing's been applied yet" (verify that assumption, don't assume
it).

## Code style

Always put comments in code (manifests, scripts) so it is understandable by
a human reader — explain what non-obvious blocks do, not just restate the
syntax.

## Environment files

Always use `.env.local` for local config — never create or reintroduce a
`.env.example`/`.env.sample` template file. `.env.local` already exists in
this repo (gitignored) and holds the real placeholder values directly; if a
new env var is needed, add it straight to `.env.local` (with a comment
explaining it) rather than adding a separate example file for someone to
copy from.

MCP servers configured in `.mcp.json` that reference `${VAR_NAME}` (e.g.
the `github` server needs `GITHUB_PERSONAL_ACCESS_TOKEN`) read from the
process environment, which is not populated automatically. Before using
such an MCP server or making authenticated GitHub calls, read the value
out of this repo's `.env.local` (e.g.
`grep GITHUB_PERSONAL_ACCESS_TOKEN .env.local`) and export it for the
current shell — don't assume it's already set.

## Gitignore

Always ensure a `.gitignore` exists in this repo — never let it be
deleted or skipped when scaffolding. It has two parts:

- A **shared baseline** kept identical (word-for-word) across all five
  `stock-*` repos: `.env`, `.env.local`, `.claude/settings.local.json`. If
  you add an entry to this shared baseline in any one repo, add the same
  line to the other four repos' `.gitignore` files too, so they stay in
  sync.
- **Repo-specific entries** below the baseline, once a platform/tool is
  chosen (e.g. Terraform's `.terraform/`, a kubeconfig, etc.) — these will
  differ per repo's tooling and should NOT be copied to siblings.
