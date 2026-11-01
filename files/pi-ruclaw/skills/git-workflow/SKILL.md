---
name: git-workflow
description: Use when creating a branch, writing a commit message, opening a merge request, resolving a rebase/merge conflict, handling a hotfix, or deciding a release/tag strategy in the RuClaw repo
---

# Git Workflow (RuClaw)

## Overview

RuClaw uses short-lived `type/*` branches -> `develop` (Dev/QA) -> `main`
(Demo) -> client release tags (on-prem). Before mutations, read the relevant Git
conventions in `docs_flow/pravila-raboty-s-git.md`; before commits/MRs also read
`docs_flow/changelog.md`. These links govern those topics, not architecture,
configuration or secret storage. Resolve material conflicts with current checks
and user instructions; do not import stale CLAUDE/config guidance from them.

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

## Changelog and authority

- One MR has one release-note decision in its first commit with a non-empty body:
  `Changelog` + `ChangelogMessage`, or an allowed `ChangelogExcluded` reason.
  Do not repeat trailers in every fix commit; use the document's path/category rules.
- Validate with `scripts/ci/check-commit-message.sh` and `check-changelog.sh`;
  inspect the latter's base/head inputs for the intended MR range.
- Never add agent co-author trailers. When the user requests implementation in this
  profile, implement's standing USER permission covers ordinary LOCAL commits of
  task-owned changes on the agreed task branch; do not request it again for each
  candidate/fix. Explicit task restrictions override this default. Inspect index/diff
  and stage only owned paths/hunks. This default does not cover amend/history rewriting,
  commits to develop/main/release or Git writes by report-only reviewer/ops roles.
- Push/MR publication, branch switching, merge/rebase/force-push require a separate
  applicable user mandate; a convention describing an operation is not permission
  to perform it. Review/advisory requests do not activate implement defaults.
  `implement`'s publication gate never permits force-push.

## When something's non-routine

Read `docs_flow/pravila-raboty-s-git.md` before acting on any of these — don't guess:

- Hotfix process (which of the two paths: rides the next release vs. emergency direct-to-`main`)
- Reverting a merged feature from `main` (and the required back-merge into `develop`)
- Migration number collisions or lock-file conflicts (`go.sum`, `pnpm-lock.yaml`) during rebase
- What belongs in `.gitignore` for this repo
- Tag/release cadence and versioning
- Any exception to the above (needs tech lead/maintainer sign-off)
