# Cross-repo write credential for image-tag bump jobs

`stock-backend`'s and `stock-frontend`'s CI need to open (and for dev,
merge) pull requests against the separate `stock-infrastructure` repo to
bump image tags — `gitops-plan.md` specified the bump-job pattern itself
but never addressed how CI in one repo gets write access to another. We
chose a fine-grained PAT, scoped only to `stock-infrastructure` with
Contents: Read/Write and Pull requests: Read/Write, stored as a repo secret
(`INFRA_REPO_PAT`) in both `stock-backend` and `stock-frontend`, over a
GitHub App or a classic PAT. A GitHub App gives shorter-lived tokens and a
cleaner audit trail but is real operational overhead — app registration,
private key secret, installation management — for a single-operator
homelab. A classic PAT would carry access to every repo on the account,
compounding risk on an account that already has one over-broad PAT sitting
exposed in `settings.local.json` (see the 2026-08-20 `.claude/` config
audit). The fine-grained PAT is the narrowest credential that still keeps
setup to "generate one token, paste it into two repo secrets."

**Considered options:**
- **GitHub App** — rejected: too much operational overhead for the actual
  risk being managed at this scale.
- **Classic PAT** — rejected: unnecessarily broad (whole-account repo
  access), and the account already has a cautionary tale about broad PAT
  exposure.
