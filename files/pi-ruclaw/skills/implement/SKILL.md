---
name: implement
description: Implement a RuClaw spec or local sub-ticket on the current feature branch, with focused checks, commit, and code-review handoff.
disable-model-invocation: true
---

# Implement for RuClaw

Implement the work described by the user, spec, or `.scratch/<TICKET>/issues/<NN>-*.md` file.

## RuClaw workflow constraints

- Respect `docs/agents/workflow.md`.
- Work on the current feature branch; do not create a new branch for normal sequential implementation.
- One RCL ticket = one branch = one MR.
- For sub-ticket work, use the sub-ticket file as the spec source for review.
- Commit the sub-ticket's work before running code-review; `code-review` diffs committed history.
- Do not add agent co-author trailers.

## Process

1. Read the referenced ticket/spec fully.
2. Inspect nearby code and project instructions before editing.
3. Identify the smallest verifiable implementation plan.
4. Prefer TDD/red-green-refactor when there is a clear seam.
5. Make small focused edits.
6. Run relevant checks frequently:
   - Go: remember `GOFLAGS=-tags=goolm` for raw `go test`/`go build`.
   - Web UI: use `pnpm`, not npm.
   - Python services: use `uv`, `ruff`, `mypy` per service.
7. Update the local sub-ticket acceptance checkboxes and `**Status:** done` when complete.
8. Commit to the current branch using RuClaw commit format: `type(RCL-XXX): summary`.
9. Run `/skill:code-review` with the correct fixed point and the sub-ticket/spec path. For broad diffs, use the exact-snapshot evidence bundle + lane review + synthesis flow from the code-review skill, not an ad-hoc live-worktree review.

## Code-review fixed point

- First sub-ticket on a fresh feature branch: `origin/develop`.
- Later sub-tickets after pushing previous work: `origin/<feature-branch>`.
- If unsure, ask before reviewing.

## Code-review quality gate

Use the project `code-review` skill, including its exact-snapshot safeguards:

- verify base/head SHAs before reviewing;
- if using subagents, give them either shell/git access or a parent-created evidence bundle;
- for large or cross-cutting diffs, split into topic lanes (`tenant-theme`, `design-contrast`, `accessibility-components`, `go-settings-api`, `generated-parity`, `ops-readiness`) and finish with synthesis;
- never accept a subagent “No findings” if it could not inspect the exact diff.

## Completion

Report:

- changed files;
- checks run;
- commit created;
- code-review result or exact command to run next;
- any remaining risks.
