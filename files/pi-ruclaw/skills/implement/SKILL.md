---
name: implement
description: "Implement a RuClaw task using plan-cycle v2: original checkpoint, short sequential plan, focused checks, final independent review and explicitly authorized publication."
disable-model-invocation: true
---

# Implement — plan-cycle v2 (default)

The main Pi writes product code. No implementation-worker fanout, old phase manifests,
mandatory interim review or ruclaw_next_cycle. Read `references/plan-cycle.md` for
operational safeguards; use profile/testing.md and actual scripts for test commands.

## Standing implement permissions

The user has authorized these defaults whenever implementation is requested in this
profile. Do NOT ask again for operations within these bounds:
- Ordinary LOCAL commits of this task's owned changes on the agreed task branch,
  including review/CI fixes and the exact candidate needed for independent review.
  Inspect the diff/index, stage only owned paths/hunks and follow Git/changelog checks.
  No unrelated staged work, forced WIP commits, amend/history rewriting or direct
  commits to develop/main/release branches under this default.
- Local Docker/Compose for isolated task-owned stands/dependencies: build/pull images,
  create/start/restart/stop/remove owned containers and their owned networks. Inspect
  wrappers and existing resource ownership/isolation first; pass explicit bounds to ops.

This is standing USER authority, not permission inferred from tool availability.
Record it in the plan instead of requesting ritual approval. Explicit task-specific
restrictions/revocations override defaults. Unclear ownership/scope is a real blocker.
No default permission for push/MR publication, branch switching, merge/rebase/force-push,
shared/production changes, global prune, volume deletion, persistent-data resets,
privileged execution, host firewall or security bypass. Obtain separate authority for
those; reviewer/ops roles retain their narrower no-product-write/no-Git contracts.

## Intake and checkpoint 0

1. Read the full task/spec and criteria, inspect Git/dirty ownership and existing
   committed progress, then read only relevant area/code/contracts. Resolve material
   requirement conflicts with the user. Do not bulk-load team instructions/history.
2. Record the approved scope/exclusions, current permissions, required checks and
   exact original base/branch. Preserve the existing base on recovery; never replace
   it with partially implemented HEAD or a moving reference. Check ancestry. Read
   git-workflow before Git operations. No automatic worktree/branch switch or push.
3. BEFORE planning or product edits call `plan_cycle_start` ALONE with
   `{"plan_path":".scratch/<ticket>/<task>/plan.md"}` (use the actual task directory).
   This saves the original task and intake reads in checkpoint 0. If an active v2
   plan exists for THIS task, resume it instead: do not recreate its base. For a
   separate task after an agreed endpoint, use the task-boundary rules below.
4. Write a SHORT sequential plan there, with TODO / INPROGRESS / DONE / BLOCKED,
   base/branch/criteria references, key decisions, permissions and next action.
   Include tests, final independent review, and publication/status/cleanup steps
   needed for the agreed endpoint. Ask only for missing scope/authority, not ritual
   approval of a purely technical plan. Call `plan_cycle_next` separately to begin.

## Task boundaries

Keep fixes/review follow-ups and authorized integration of the SAME task in its
existing cycle. A new standalone task/branch after an agreed endpoint needs a fresh
session and compact handoff, not more TODOs in the old task's plan. A rejected start
is not permission to append an unrelated task. Never rotate sessions to hide failed
gates: link prior results/open findings and resolve the new task's own immutable base.
Keep original bases as historical evidence, not as the current base of a new task.
Before handoff settle all children and make the old writer idle; preserve scope,
permissions with their user sources, HEAD/dirty ownership, open gates/resources and
next action. Do not infer broader permissions in the new session. `stop` restores
ordinary history; stop/start is not a clean-context reset. No automatic new-session,
branch switch or abandonment of mandatory gates. See `references/plan-cycle.md`.

## One step at a time

- Take the first unfinished step. BEFORE TODO -> INPROGRESS reread relevant changed/
  created files; do not treat deleted files as present. The original task is already
  in checkpoint 0: do not reload it merely because context changed.
- Do the coherent step yourself. Architecture/interfaces/stubs may be a separate
  step, then implementation, tests/fixes and final review. Intermediate code may be
  broken when explicitly recorded; remove unintended stubs by the final candidate.
- Use focused regressions while editing; reserve expensive integrated checks for a
  stable candidate. Do not repeat unchanged tests just for a new context/commit.
- Save a brief result, important decisions and changed/created/deleted paths in the
  plan; details/logs go to linked result files, not a growing history in plan.md.
  Keep completed steps to a short outcome + evidence link; do not accumulate command
  histories, hash inventories, old scopes or finding dispositions in the plan.
  Under the standing local-commit permission above (unless restricted), commit the
  step's owned source changes without another permission round; do not force a
  WIP commit only for a reset or absorb unrelated work. DONE means the STEP is
  performed, not that all requirements or delivery gates passed.
- Set DONE, finish all tools/children, then call `plan_cycle_next` ALONE. It uses
  checkpoint 0 + the updated plan + the new step's conversation. No Git rollback.
- If a step exposes a bad plan: BLOCKED + cause/partial work, stay in this context,
  revise the technical plan and statuses, then continue. Requirements/permissions
  still belong to the user. Genuine unresolved blockers go to the user; no endless
  retries or silent waivers. next refuses INPROGRESS/BLOCKED.

Plan and checkpoint-read invalidation are frozen AT THE BOUNDARY. Within the step,
fresh read/edit/write results extend the tail and supersede the step-start plan.
Do not replace prefix messages on each small edit. Compaction is cancelled while
plan-cycle is active; split oversized steps or save a handoff rather than disabling
safeguards. New user instructions survive transitions verbatim.

## Final review and fixes

After coherent implementation, focused regressions and applicable cheap CI-preflight
(profile/testing.md), commit the exact candidate under the standing local-commit
permission (unless restricted) without asking again, and launch fresh
`ruclaw-plan-reviewer` asynchronously. Do not wait for every expensive check merely
to start review. Run required heavy verification alongside review on the SAME fixed
candidate when resources are isolated; otherwise serialize. Reviewer remains static
and report-only; the parent owns execution. Do not edit inputs used by either run:
finish/stop them before fixes, or use separately verified immutable test inputs.
Results describe their actual candidate, never automatically the later HEAD. Settle
all runs before plan_cycle_next, publication or acceptance; no pending gate is passed.
Verify resolved
role policy first: no project/global/skills inheritance, read/bash/write, report-only,
output:false/outputMode:inline. Assign full task/criteria, exact original base/head,
relevant evidence/authority and a unique writable result directory under task scratch.
The role inspects the entire task increment and affected consumers; tests remain the
parent's responsibility. Do not substitute self-review or tool success for review.
See `references/result-contract.md` for short/detail artifact transport, not an old
phase ledger. No fixed whole-diff fanout; extra independent scrutiny must address a
concrete risk/gap rather than repeat already valid coverage.

Read all short indexes and the relevant details, validate findings, then turn
confirmed fixes into a new short sequential plan. Identify the violated invariant
and its supported variants before fixing; test the class, not just the reproducer.
If follow-up again exposes the same boundary flaw, pause for a focused design/contract
test instead of another patch-only loop. Follow-up reviews inspect the
previous reviewed head..new head plus affected invariants, carrying unchanged
coverage honestly. Keep old reports/dispositions; a new SHA does not erase blockers.

## Completion

Reconcile ALL criteria/findings and required checks at the final candidate. Record
exact commands/results, fresh vs reused evidence and remaining gates. Requirement
outcome and delivery readiness are separate; required failed/skipped/blocked cases
are not passed. A user-approved source-only endpoint does not waive live acceptance.

Only publish when authorized; when publication is a required gate, non-force push
and verify origin contains the reviewed head before task done. Stop on concurrent
branch changes/failure; no automatic rebase/force push. Mark task **Status: done**
only after all its agreed mandatory gates, not merely because plan steps say DONE.
Clean up only owned resources, finish all children, give a short result + paths.

In tmux runner mode, its user mandate includes the requested publication gate.
After full task completion call runner_finish ALONE with done; a real blocker/error
uses blocked/failed. Never send done just to start the next task. Leave Pi idle and
open after finishing: another executor may already be using the checkout.

## Recovery

For an existing v2 session: use /plan-cycle status, its saved plan and current
step-relevant result files; inspect real Git/resources without repeating onboarding.
If switching sessions, first make the old writer idle and preserve a compact
handoff with original bases/HEAD/dirty ownership, open gates/resources and next step.
Legacy work-cycles sessions must use `pi-ruclaw --legacy-cycles --session <id>` and
`references/resume.md`, not silently migrate or invoke this new skill from scratch.
