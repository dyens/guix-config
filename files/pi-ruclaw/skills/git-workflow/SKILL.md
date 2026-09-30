---
name: git-workflow
description: Use when creating a branch, writing a commit message, opening a merge request, resolving a rebase/merge conflict, handling a hotfix, or deciding a release/tag strategy in the RuClaw repo
---

# Git Workflow (RuClaw)

## Overview

RuClaw uses a lightweight branch model, not trunk-based or classic GitFlow: short-lived `type/*` branches -> `develop` (Dev/QA) -> `main` (Demo) -> client release tags (on-prem). Full rationale and edge cases: `docs_flow/pravila-raboty-s-git.md`.

## Quick reference

| Branch prefix | Commit type | Purpose |
|---|---|---|
| `feature/` | `feat` | New functionality |
| `bugfix/` | `fix` | Pre-release bug fix |
| `hotfix/` | `hotfix` | Emergency fix on Demo/client |
| `chore/` | `chore` | Deps, config, CI |
| `refactor/` | `refactor` | Risky refactor, same external contract |
| `docs/` | `docs` | Docs-only change |

- **Branch name:** `type/RCL-XXX-kratkoe-opisanie`
- **Commit message:** `type(RCL-XXX): summary in English` — validate with `sh scripts/ci/check-commit-message.sh "msg"` before committing
- **Merge to `develop`:** squash merge, needs 1 approve + green CI, MR must reference the RCL Jira ticket
- **Promotion `develop` -> `main`:** whole `develop` at once via merge commit (no squash), only after a tech-lead-announced freeze + full QA pass on Dev — never a partial/selective promotion
- **Sync with `develop`:** rebase your branch (`git fetch && git rebase origin/develop`), unless the branch is shared with others (then merge instead)
- **Force-push:** only your own branch, only after a rebase — never `develop`/`main`

## When something's non-routine

Read `docs_flow/pravila-raboty-s-git.md` before acting on any of these — don't guess:

- Hotfix process (which of the two paths: rides the next release vs. emergency direct-to-`main`)
- Reverting a merged feature from `main` (and the required back-merge into `develop`)
- Migration number collisions or lock-file conflicts (`go.sum`, `pnpm-lock.yaml`) during rebase
- What belongs in `.gitignore` for this repo
- Tag/release cadence and versioning
- Any exception to the above (needs tech lead/maintainer sign-off)
