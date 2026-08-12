---
name: pr-description
description: Use whenever the user asks to write, generate, draft, or update a pull request description, "PR description", "PR summary", or wants help filling out a PR before opening or updating one on GitHub. Also trigger when the user asks what a PR/branch changes and wants that written up, or says "open a PR" without already having a description ready. Reads the actual diff and commit history rather than guessing, and produces a description grounded in what changed and why — not a generic template.
---

# PR Description

Generate a pull request description from the real changes on a branch — not from what the user remembers doing, and not a boilerplate template with blanks.

## Why this needs its own pass

A PR description that just restates the diff ("changed file X, added function Y") is worse than useless — reviewers can already see the diff. A good description tells the reviewer what they can't get from the code: why this change exists, what tradeoffs were made, what the risk surface is, and what to actually test. Get that from commit messages, the branch's actual content, and the user — not invention.

## Workflow

1. **Establish the diff range.** Figure out the base branch (usually `main` or `master`; ask if ambiguous) and the current branch. Use `git log --oneline <base>...HEAD` and `git diff <base>...HEAD` to see every commit and the full changeset that will land in the PR — not just the latest commit.

2. **Read the commits, not just the diff.** Well-written commit messages (especially atomic ones — see the `atomic-commit` skill) already carry the "why" for each logical piece. Pull that motivation forward into the description instead of re-deriving it from code alone. If commit messages are sparse or just say "fix stuff", read the actual diff hunks to understand intent, and consider asking the user for missing context rather than guessing.

3. **Identify what actually matters to a reviewer:**
   - What problem does this solve, or what capability does it add?
   - What's the blast radius — which parts of the system does this touch, and could it affect anything the diff doesn't obviously show (migrations, config, shared utilities)?
   - Are there deliberate tradeoffs or things intentionally left out of scope?
   - What should a reviewer specifically check or test?

   Skip restating routine mechanical changes line-by-line; group them ("renamed X across the module") instead of listing every occurrence.

4. **Check for anything a description should surface as risk**, not hide: breaking changes, migrations, feature flags, TODOs left in, or follow-up work not done in this PR. If you find something that looks unfinished or risky, mention it in the description rather than smoothing over it.

5. **Draft the description** using the structure below, then show it to the user for confirmation before it's used to open or update a real PR — posting to GitHub is a visible, shared action, so don't call `gh pr create`/`gh pr edit` without the user's go-ahead on the content first.

6. **If the user wants it opened or updated on GitHub**, use `gh pr create` or `gh pr edit` with the confirmed body passed via heredoc so formatting survives, per the standard PR-creation practices already in effect for this environment.

## Description structure

Default to this shape; drop sections that don't apply rather than leaving them empty, and add a section (e.g. "Migration notes", "Breaking changes") when the change genuinely needs one:

```markdown
## Summary
<1-3 bullet points: what changed and why, in plain language>

## Details
<Only if the summary bullets aren't enough — context on approach, tradeoffs, or things deliberately out of scope. Skip this section for small/self-explanatory PRs.>

## Test plan
<Bulleted checklist of what was tested or should be tested — commands run, scenarios covered, edge cases to check manually>
```

Keep the title under ~70 characters, written as a statement of what the PR does (e.g. "Add retry logic to webhook delivery"), not a vague label like "Updates" or "Fixes".

## Grounding rules

- Never invent test results, benchmarks, or reviewer instructions that weren't actually run — if the test plan is aspirational ("should be tested by..."), phrase it as a checklist for the reviewer, not a claim that it happened.
- If the branch mixes several unrelated changes, say so plainly in the summary rather than writing a description that pretends it's one cohesive change — that's a signal worth surfacing, not papering over (and may mean the user actually wants separate PRs).
- If you can't tell why a change was made from commits, diff, and conversation context, ask the user rather than fabricating a rationale.
