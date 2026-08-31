# FinOps guardrails for the AWS tier: Floci-driven cost estimates and tag-filtered budget alerts, visibility only

Status: accepted

No real AWS account exists yet — `0004-aws-production-dr-architecture.md`
deliberately validates the entire architecture against **Floci** (a local,
free AWS API emulator) before any real, billable account is provisioned.
This ADR extends that same "validate before spend" philosophy to cost:
cost visibility starts at design time, not after the first real bill.

**Scope, deliberately narrow**: this covers cost *visibility* and
*budget guardrails* only — tagging, pre-cutover cost estimates, and
threshold notifications. It does not cover automated cost optimization
(rightsizing, Savings Plans purchase automation, scaling down on a budget
breach). Optimization needs real usage data to act on, which doesn't
exist pre-cutover; that's a later, separate decision once the AWS tier is
actually running.

**Pre-cutover cost estimation**: CI runs Terraform plans against Floci
(same plan step `0007-aws-cicd-iac.md` already runs for validation) and
feeds the result to **Infracost**, posting a projected monthly cost diff
as a PR comment alongside the existing `plan` output. This gives cost
visibility on every infrastructure change before any of it is real —
someone changing an instance type or adding a NAT gateway sees the dollar
impact in the same PR, not in a bill weeks later.

**Cost allocation tags**: every taggable AWS resource carries `environment`
(`production` | `dr`) and `component` (`backend` | `frontend` | `postgres`
| `shared-infra`) tags, reusing the `{app, environment}` vocabulary
`0007-aws-cicd-iac.md` already established for the promotion pipeline —
no new taxonomy invented for FinOps specifically.

**Budget guardrails**: **AWS Budgets**, not CloudWatch Billing Alarms —
Billing Alarms are account-wide only and can't filter by tag, which would
throw away the granularity the tagging scheme above exists to provide.
One budget per `{environment, component}` pair, seeded from that pair's
Infracost projection as the initial amount (the only principled starting
number available pre-cutover; revisit after the first real month of
billing shows actual usage). Two-tier severity — `warning` at 80%,
`critical` at 100% — reusing the exact severity taxonomy
`0003-observability-stack.md`'s homelab work already established
(`CONTEXT.md`'s "Alert severity"), rather than inventing a third scheme
for AWS.

**Notification, not enforcement**: a budget breach notifies a dedicated
Discord channel (AWS Budgets → SNS → the same webhook-notification
pattern already used for the homelab's category-routed alerts) and
nothing else. This directly fills the gap
`0008-aws-observability-secrets.md` left open ("an equivalent CloudWatch
Alarms → Discord path needs its own decision"). No automated enforcement
action was considered viable: this is production/DR infrastructure with
human-gated Terraform applies already (`0007`), and DR's warm-standby app
tier is load-bearing for the minutes-scale RTO target
(`0005-aurora-global-database-dr-failover.md`) — an automation that
scaled something down because a budget was crossed could silently
undermine that guarantee. A human decides what to do about a budget
breach, the same way a human already decides whether to `terraform apply`.

**Considered and rejected**:
- **CloudWatch Billing Alarms instead of AWS Budgets** — account-wide
  only, no tag filtering; would only answer "did total spend cross X,"
  not "did DR spend cross X" or "did the backend's spend cross X."
- **Automated cost-driven enforcement** (auto-scale down, block applies
  on breach) — risks silently violating the DR warm-standby guarantee
  `0004`/`0005` depend on; rejected in favor of notify-only, matching this
  project's human-gated-apply philosophy.
- **Re-examining DR's warm-standby topology as part of this ADR** — almost
  certainly the largest cost driver here, but it's load-bearing for the
  RTO target, not arbitrary. Revisiting it is a separate, much larger
  decision than "how do we get visibility into what it costs." If these
  guardrails later reveal DR costs more than expected, that finding can
  motivate a future ADR — this one doesn't presuppose the answer.
- **A three-tier `info`/`warning`/`critical` severity scheme** — rejected
  for the same reason `0003`'s homelab alerting rejected it: more
  granularity than useful here, and inventing a second AWS-specific
  scheme when a project-wide one already exists would fragment the
  vocabulary for no benefit.

## Consequences

- Every PR touching AWS Terraform now shows a cost diff alongside the
  existing `plan` output, before real spend is even possible — cost
  review becomes part of normal PR review, not a separate FinOps ritual.
- Budget thresholds start as Infracost estimates, not measured reality —
  expect to revise them after the first real billing cycle; treat the
  initial numbers as provisional.
- A third notification channel/pattern now exists (homelab Alertmanager →
  Discord, `0008`'s not-yet-built AWS observability → Discord, and now
  AWS Budgets → SNS → Discord for cost specifically) — same downstream
  channel, three different upstream triggers to keep straight.
- This ADR does not make AWS cheaper; it makes AWS cost *visible and
  bounded*. Actually reducing DR's cost, if that's ever wanted, is future
  work explicitly out of scope here.
