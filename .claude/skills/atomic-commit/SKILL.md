---
name: atomic-commit
description: Use whenever the user asks to commit changes, "commit this", "make a commit", "clean up my commits", or wants git history organized into atomic/logical commits instead of one big dump. Splits a working tree's changes into separate, self-contained commits — one logical change per commit — and writes concise conventional-style messages that explain why, not what. Trigger this even if the user just says "commit" with no other detail, since the default behavior should always be atomic, not a single catch-all commit.
---

# Atomic Commit

Turn the current working tree changes into a sequence of small, reviewable, logically atomic commits — instead of one commit that bundles unrelated work.

## Why atomic commits matter

A commit should represent exactly one logical change: a single bug fix, one feature slice, one refactor, one config tweak. When commits are atomic:
- `git bisect` and `git revert` work on individual changes without collateral damage
- Reviewers can understand and approve each piece independently
- History reads as a narrative of *why* the code evolved, not a diff dump

If the user's working tree only contains one logical change, a single commit is correct — don't manufacture extra splits just to look thorough.

## Workflow

1. **Survey the tree.** Run `git status` and `git diff` (staged and unstaged) to see everything that changed. Never assume — read the actual diff content, not just filenames, since two changes in the same file can still be logically unrelated (e.g. an unrelated formatting fix mixed into a feature change).

2. **Check for anything that shouldn't be committed.** Scan the diff for secrets, credentials, `.env` files, or large/binary artifacts that look accidental. Flag these to the user before staging anything — don't silently commit or silently exclude them; ask.

3. **Group changes into logical units.** Cluster hunks/files by the change they belong to, not by file type or directory. Typical groupings:
   - A feature and its tests together (they're one logical change)
   - A refactor separate from a behavior change riding along with it — split these even if they touch the same lines, since mixing "moved code" with "changed code" is exactly what atomic commits exist to avoid
   - Formatting-only or whitespace-only changes as their own commit, separate from functional changes
   - Unrelated bug fixes each get their own commit, even if small

   Use `git add -p` (or stage whole files with `git add <path>` when a file is wholly one logical unit) to build each commit's staged set precisely. If a single file mixes two unrelated changes, use `git add -p` to select only the relevant hunks.

4. **Show the user the plan before committing anything**, unless they've asked you to just go ahead. A short list is enough: "I see N logical changes: (1) ..., (2) ..., (3) .... I'll commit them separately." This is a good moment to pause because splitting is a judgment call and the user may see the changes differently than you do.

5. **Commit each unit separately**, in a sensible order (e.g., foundational/refactor commits before the feature commits that build on them). For each commit:
   - Stage only that unit's changes
   - Run `git diff --staged` to confirm exactly the intended hunks are staged
   - Write the message per the format below
   - Commit
   - Move to the next unit

6. **Verify at the end.** Run `git status` to confirm the tree is clean (or that only intentionally-excluded changes remain) and `git log --oneline -n <N>` to show the resulting commits to the user.

## Commit message format

Use conventional-commit style: `type(scope): summary`

- **type**: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`, `build`, `ci` — pick the one that matches what actually changed, not what sounds most impressive
- **scope**: the module/area affected (optional if the change is repo-wide or scope would be noise)
- **summary**: imperative mood, lowercase, no trailing period, under ~72 chars

The subject line says *what* changed; if the *why* isn't obvious from the subject and diff alone, add a short body (a couple sentences, wrapped) explaining the motivation — the problem being solved, a constraint, or context a future reader won't have from the code itself. Don't restate the diff in prose.

**Examples:**

Input: split out a new `formatCurrency` helper used by both the invoice and receipt views, no behavior change
Output:
```
refactor(billing): extract formatCurrency helper

Invoice and receipt views had duplicated rounding logic that was
drifting out of sync; centralizing it avoids the next divergence.
```

Input: fixed a null pointer when a user has no billing address
Output:
```
fix(checkout): handle missing billing address on guest orders

Guest checkout skips address collection, so the summary page must
not assume one exists.
```

Input: bumped a lint config and reformatted the touched files
Output:
```
style: reformat per updated lint config
```

## Git safety practices

These apply regardless of how many commits are produced:

- Never use `git commit --amend` on commits that may already be pushed/shared — always create new commits, per the repo-wide git safety rules already in effect.
- Never force-push (`git push --force`) as part of this workflow. If asked to push, use a normal push and ask first per the standard risky-action confirmation rules.
- Never stage or commit files that look like secrets, credentials, or `.env` files — surface them to the user instead.
- Never use `git add -A` or `git add .` — atomic staging requires picking specific files/hunks, and a blanket add defeats the purpose (and risks scooping up files the user didn't mean to include).
- Always end every commit message with:
  ```

  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  ```
  (blank line, then the trailer), matching the standard commit-authoring convention already in effect for this environment. Pass multi-line messages via a heredoc so formatting survives, e.g. (bash):
  ```bash
  git commit -m "$(cat <<'EOF'
  fix(checkout): handle missing billing address on guest orders

  Guest checkout skips address collection, so the summary page must
  not assume one exists.

  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  EOF
  )"
  ```
  On Windows PowerShell, use a single-quoted here-string (`@'...'@`) instead.
