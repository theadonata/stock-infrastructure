# Terraform+Terragrunt with directory-per-environment, GitHub OIDC, and human-gated apply

Status: accepted

**IaC tooling**: Terraform stays the tool (already used for the homelab's
bootstrap layer per `0002-gitops-deployment-architecture.md`), wrapped in
**Terragrunt** for DRY configuration across {region × environment}
combinations. Environments are separated **by directory** — one
`terragrunt.hcl`/state file per region/environment — not by Terraform
workspace. Workspaces share the same backend/state-file family and
provider configuration, so isolation between production and DR would rest
on remembering to `terraform workspace select` correctly rather than on a
structural barrier; for infrastructure explicitly built to survive a
region outage, that shared-state blast radius was judged an unacceptable
risk to take on purely for DRY convenience. Terragrunt's `include` blocks
give the same DRY benefit without it.

**CI → AWS auth**: GitHub **OIDC federation** — short-lived, per-workflow
IAM roles — not static IAM access keys. This avoids adding a second class
of long-lived credential to rotate and leak-monitor, on top of the
existing cross-repo `INFRA_REPO_PAT` (`0001-cross-repo-bump-credential.md`).

**Apply gating**: `plan` runs automatically in CI on every PR touching AWS
infrastructure, for visibility. `apply` requires a human to trigger it (a
GitHub Environment with required reviewers). This mirrors the human-gated
principle ADR 0002 already established for staging's promotion gate — not
because AWS is technically unreachable from hosted runners (unlike the
homelab box, which was ADR 0002's actual reason for keeping Terraform CI
validate-only), but because Terraform changes to production/DR
infrastructure carry the highest blast radius of any change type in this
system.

**Promotion pipeline**: extends the existing pattern rather than
introducing a new one. A **third bump job** (staging → production) opens a
PR against `values-production.yaml`, same as the existing dev/staging bump
jobs, still ending in a human-triggered Argo CD sync — now against the AWS
EKS clusters. The DR region does **not** get its own promotion path: one
`values-production.yaml`, two Argo CD Applications (primary cluster + DR
cluster), so a single promotion event deploys to both regions in lockstep.
A separate DR promotion path was considered and rejected — it would let DR
silently drift out of sync with production, quietly breaking the
warm-standby guarantee `0004` and `0005` depend on.

## Consequences

- Every AWS infrastructure change needs a human "approve" click in CI
  before it takes effect — including infra fixes made *during* an
  incident. This doesn't block the automated DB/DNS failover in `0005`,
  which operates entirely outside Terraform via Lambda/Step Functions,
  precisely so this gate never sits on the critical recovery path.
- `CONTEXT.md`'s Bump job/Promotion/Sync definitions now apply to a third
  {app, environment} pair without needing new terms — the vocabulary was
  already general enough.
