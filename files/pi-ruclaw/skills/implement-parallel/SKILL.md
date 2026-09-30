---
name: implement-parallel
description: "Implement several unblocked RuClaw sub-tickets at once with Pi subagents: one isolated worktree lane per sub-ticket, reviewed and merged back into the current feature branch by the parent."
---

# Implement in parallel for RuClaw + Pi

Parallel alternative to running `/skill:implement` once per sub-ticket. Same final shape: commits land on the current RuClaw feature branch, one RCL ticket = one branch = one MR.

This skill uses **Pi subagents**, not Claude Code primitives. If subagent tools are not available yet, call `subagents_enable`; on the next turn/use, load the `pi-subagents` skill guidance if needed.

## Invariants

Read `docs/agents/workflow.md` first. This skill is step 4-bis of that flow.

- One RCL ticket = one branch = one MR.
- Per-sub-ticket worktrees/branches are temporary implementation lanes only.
- The parent agent owns orchestration, review, merge, cleanup, and final reporting.
- Child agents do not merge to the feature branch.
- Child agents do not create Jira issues.
- Do not add agent co-author trailers.

## When NOT to use this

- Fewer than two unblocked sub-tickets: use `/skill:implement`.
- Unblocked sub-tickets likely touch the same files or same tight semantic seam.
- A sub-ticket is `ready-for-human` or needs non-repo access/facts.
- The feature branch has uncommitted changes.
- The current feature branch tip is not pushed.

## 1. Establish the ground

Before spawning anything, verify and state:

1. Current branch is the ticket feature branch, e.g. `feature/RCL-XXX-short-slug`.
2. Working tree is clean.
3. Branch tip is pushed and will be the shared base for every lane.
4. `.scratch/<TICKET>/issues/` exists.
5. Unblocked tickets are `**Status:** ready-for-agent` and all `Blocked by` tickets are `done`.

Record:

- feature branch name;
- shared base commit SHA;
- ticket ID;
- current frontier.

## 2. Pick the batch

From the unblocked frontier:

1. Drop tickets that should not run in parallel.
2. Inspect likely touched areas to avoid overlap.
3. Cap the batch at four lanes.
4. Present the proposed batch to the user and wait for approval.

For each candidate show:

- ticket file;
- why it is safe to parallelize;
- suspected touched areas;
- any risk.

## 3. Spawn one Pi subagent per sub-ticket

Use Pi subagents with one isolated worktree lane per sub-ticket. Prefer async parallel fanout. In Pi terms, use the subagent workflow facilities (`workflowScript` with `runs.all(...)`) when available, or direct async child runs if that is the local API surface.

Each child prompt must include the **full text** of the sub-ticket, not just a path, because a child starts with a smaller/fresh context.

Each child receives:

- objective: implement exactly this sub-ticket;
- repo/cwd and shared base commit;
- authority: edit only its isolated worktree/lane;
- temporary lane branch name: `wt/RCL-XXX-NN-slug`;
- required reading before edits:
  - `AGENTS.md` files;
  - `docs/agents/workflow.md`;
  - `CONTEXT.md`;
  - relevant ADRs/docs near touched code;
  - the referenced spec if any;
- build rule: for raw Go commands use `GOFLAGS=-tags=goolm`;
- package-manager rules: `pnpm` for UI, `uv` for Python services;
- implementation instruction: follow `/skill:implement` semantics, but do not merge;
- review instruction: run `/skill:code-review` for its own lane using shared base as fixed point and its sub-ticket as spec source; if the lane diff is broad/cross-cutting, use the exact-snapshot evidence bundle + topic lanes + synthesis flow from the code-review skill;
- expected report:
  - branch/lane name;
  - commits created;
  - acceptance criteria satisfied/not satisfied;
  - changed files;
  - checks run and results;
  - code-review summary;
  - blockers or risks.

Do not let children spawn further subagents unless explicitly authorized.

## 4. Parent review of every returned lane

A child report is a claim, not evidence. For each lane before merging:

1. Inspect commits and diff against the shared base / feature tip.
2. Re-run the relevant checks yourself where practical.
3. Check every acceptance criterion in the sub-ticket.
4. Check the lane did not touch files outside its slice.
5. Check it did not implement another ticket's scope.
6. Apply the `code-review` skill's exact-snapshot safeguards: verify base/head SHAs, use a parent-created evidence bundle when reviewer subagents lack git/shell, and treat inability to inspect the exact diff as infrastructure failure.
7. For broad/cross-cutting lane diffs, run topic lanes and synthesis before approving the merge.

If a lane fails review, send it back to the same child with specific findings when possible. Do not silently fix substantial child-owned work in the parent unless the user approves.

## 5. Merge lanes serially

Merge into the feature branch one lane at a time, never in parallel.

For each approved lane:

```bash
git switch <feature-branch>
git merge --no-ff wt/RCL-XXX-NN-slug
# run the relevant suite/checks
git push
```

After each merge, run relevant checks. Semantic conflicts can appear even when Git has no textual conflict.

On merge conflicts, resolve by intent. If resolution is non-trivial, pause and ask or route back to the responsible child/lane.

## 6. Update local sub-ticket state

For each merged sub-ticket:

1. Tick completed acceptance criteria.
2. Set `**Status:** done`.
3. Update `.scratch/<TICKET>/README.md` frontier if present.

## 7. Tear down

After successful merge and push:

- remove worktrees;
- delete local `wt/*` branches;
- delete remote temporary `wt/*` branches if pushed;
- confirm `git worktree list` has no temporary lane;
- confirm `git branch --list 'wt/*'` is empty.

If any lane remains unmerged, do not delete it; report its exact state.

## Final report

Report:

- sub-tickets merged;
- sub-tickets returned for rework;
- sub-tickets skipped and why;
- checks run after each merge;
- current feature branch state and push status;
- newly unblocked frontier;
- cleanup confirmation for worktrees and `wt/*` branches.
