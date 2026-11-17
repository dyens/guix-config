---
name: implement
description: "Implement a RuClaw task with extension-owned structured steps, bounded context, focused checks and final independent review."
disable-model-invocation: true
---

# Implement — structured tasks (default)

The main Pi writes product code. Extension owns task state, transitions and generated
plan.md. No implementation workers, phase manifests, mandatory interim review or
routine report files. Read references/plan-cycle.md for safeguards once when needed;
profile/testing.md and actual scripts supply check commands. Do not reload guides
merely because a step changed. Keep user-facing progress quiet: meaningful blockers,
material decisions/questions and a short final result, not an execution diary.

## Standing implement permissions

The user has authorized these defaults whenever implementation is requested in this
profile. Do NOT ask again for operations within these bounds:
- Ordinary LOCAL commits of this task's owned changes on the agreed task branch,
  including review/CI fixes and the exact candidate needed for independent review.
  Inspect diff/index, stage only owned paths/hunks and follow Git/changelog checks.
  No unrelated staged work, forced WIP commits, amend/history rewriting or direct
  commits to develop/main/release branches under this default.
- Local Docker/Compose for isolated task-owned stands/dependencies: build/pull images,
  create/start/restart/stop/remove owned containers and their owned networks. Inspect
  wrappers and existing resource ownership/isolation first; pass explicit bounds to ops.

This is standing USER authority, not permission inferred from tool availability.
Explicit task-specific restrictions/revocations override defaults. Unclear ownership
or scope is a blocker. No default permission for push/MR publication, branch switching,
merge/rebase/force-push, shared/production changes, global prune, volume deletion,
persistent-data resets, privileged execution, host firewall or security bypass.
Obtain separate authority; reviewer/ops retain their narrower no-product-write/no-Git contracts.

## Intake and plan

1. Read the full task/criteria. Inspect Git/dirty ownership and existing progress,
   then only relevant code/contracts. Resolve material requirement conflicts with
   the user. Read git-workflow before Git operations. No bulk onboarding or archive.
2. Resolve immutable original base, agreed branch, scope/exclusions, authority and
   required acceptance/delivery gates. Preserve this base on same-task recovery;
   check ancestry, never replace it with partially implemented HEAD or a moving ref.
3. Call task_plan ALONE before product edits. Supply task-local scratch plan_path,
   a compact context with those facts and sequential steps. IDs start at 1; needs
   names earlier step IDs whose results will be needed. Include focused tests,
   final independent review and agreed publication/status/cleanup gates. First step
   becomes active automatically; no separate start/next, manual statuses or plan approval ritual.
4. Existing structured tasks resume from injected current step, notes and handoff;
   no restart or routine task_get. Existing Markdown v2 sessions keep their old
   plan_cycle_start/plan_cycle_next protocol until an explicit fresh-session handoff.
   Do not silently migrate legacy work-cycles; use --legacy-cycles and references/resume.md.

## Work a coherent step

- Execute current active step yourself. A step is a useful increment, not one edit,
  one tool call or one test. Intermediate code may be broken if the handoff says so.
- Read only missing/stale relevant sources. Verified unchanged reads can survive a
  boundary; there is no mandatory reread before each status change. New edit/write/read
  results supersede older bytes within the step. Check uncertain external changes.
- Run focused regressions while editing; reserve expensive integration for a stable
  candidate. Do not repeat checks just for a new context, commit or report format.
- Commit owned source changes under standing permission when useful; no forced WIP
  commit for a context transition and no unrelated changes.
- Finish all tools/children, then task_complete ALONE with current step id, SHORT
  result, actual checks and only what the next step needs in handoff. Usually a few
  sentences, no separate result file. Extension observes Git metadata (not ownership
  or proof of checks); do not manually inventory hashes/paths it already records.
- notes is a REPLACEMENT for small living decisions, open findings/gates and owned
  resources, not a growing diary. Retain unresolved items; discard obsolete detail.
  Extension automatically finishes this step, activates the next and resets context.
  Completed history remains available via task_get(id), only when actually needed.
- If the plan is wrong: task_block(reason) preserves partial work/debugging context.
  task_replan supplies remaining work, keeps stable unfinished IDs, cancels omitted
  unfinished steps with a reason, and allocates IDs for new steps. No reset during
  replanning. Do not expand scope/authority or erase required gates. Real unresolved
  blockers go to the user, not endless retries or silent waivers.

Do not edit generated plan.md; session entries are authoritative. /task_get_status
is a human command (Tasks: done/total. Plan: path), not an LLM tool or startup ritual.
Plan snapshot and carried reads are frozen at boundaries, preserving prefix cache.
Compaction is cancelled while active: split oversized steps, not disable safeguards.
New user instructions and question/answer evidence survive verbatim.

## Final review and fixes

After coherent implementation, focused regressions and applicable cheap CI-preflight,
commit the exact candidate under standing permission (unless restricted). Launch fresh
ruclaw-plan-reviewer asynchronously, with resolved no project/global/skills inheritance,
read/bash/write, report-only, output:false/outputMode:inline. Assign full criteria,
original base, exact head, authority and a unique task-local result directory.
Read references/result-contract.md for the compact result transport when launching.

Run required heavy checks alongside static review on the SAME fixed candidate only
with isolated resources; otherwise serialize. Do not edit their live inputs. Finish
or stop readers/tests before fixes, transitions or acceptance. Results identify the
actual candidate; a later HEAD does not inherit them automatically. A tool success
or self-review is not independent review. Unavailable review/checks remain open gates.

Read all findings and coverage gaps, validate relevant evidence, and task_replan for
confirmed fixes. Track open IDs and concise dispositions in notes/handoff; details
only when substantial. Never rewrite historical reviewer evidence. Follow-up covers
previous reviewed head..new head and affected invariants, retaining valid coverage.
A repeated invariant defect needs a design/contract test, not another patch-only loop.

## Completion and task boundaries

Reconcile ALL criteria/findings and required checks at the final candidate. Record
actual commands/results and any reused evidence with input-equivalence justification;
short inline checks suffice, logs/details only when useful. Failed/skipped/pending
mandatory gates are not passed. Requirement outcome and delivery readiness differ;
a source-only endpoint does not prove live acceptance.

Only publish when authorized. If publication is mandatory, non-force push and verify
origin contains the reviewed head. Stop on concurrent branch changes/failure; no
automatic rebase/force push. Task counts describe steps, NOT acceptance. Finish owned
cleanup/children and give a short result, checks and remaining risks, no routine report.
In tmux runner mode the user mandate includes its publication gate. runner_finish
ALONE with done only after ALL agreed gates; real blockers/errors use blocked/failed.
Leave Pi idle and open; another executor may already be using the checkout.

Fixes/reviews/integration of the SAME task stay in its cycle. New standalone work
after an agreed endpoint uses a fresh session with compact handoff: user-sourced scope/
authority, original base/HEAD/dirty ownership, open gates/resources and next action.
Make old writer idle and settle children first. No automatic branch/session switch,
gate waiver or abandoning work. /plan-cycle stop restores ordinary history; stop/start
is not a clean reset. Existing scope/permissions cannot be broadened by a new plan.
