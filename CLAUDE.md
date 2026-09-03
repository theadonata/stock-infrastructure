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

- Prefer setting a `GitHub Pull Request` field on the issue if the project
  has one (STOCK does — a project-scoped short-text custom field, added via
  Project settings → Issue types → \<issue type\> layout in the Jira UI, not
  creatable end-to-end via the REST API for team-managed projects; a
  field created purely through `POST /rest/api/3/field` has a *global*
  context and won't be settable on a team-managed project's issues until a
  human attaches it to that issue type's layout by hand).
- If no such field exists yet on the project, add a plain comment with the
  PR link instead — don't block the update on getting a field added first.
- If a field is later added and a comment already carries the same link,
  move the value into the field and remove the now-redundant comment.

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
