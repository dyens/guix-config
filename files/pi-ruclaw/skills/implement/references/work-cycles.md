# Workflow phase transitions (v2)

Read when PREPARING a transition, not after every reset. Recovery starts with
`resume.md`, not implement onboarding. Conversation is working memory; do not move
its entire history into a state file and then reread it.

## Phase boundaries, not micro-step boundaries

A phase has an explicit exit condition:
- implement -> review: coherent increment + focused checks, committed under actual
  Git authority; do not wait for all criteria of a large task before first review;
- review -> fix or verify: actual independent review obtained; gaps/pending overall
  acceptance remain explicit, not a premature MERGE or done;
- fix -> review: confirmed issue group resolved + affected regressions + committed
  candidate; follow-up carries unchanged evidence;
- verify -> fix or publish: final required checks evaluated on the candidate;
- publish: verified non-force publication/status/owned cleanup, then completion.

Choose a reviewable increment before implementing. Several related changes/tests
belong in ONE phase. No routine reset after a test, finding, small fix or navigation
exercise. If an investigation keeps expanding, decide scope/design with the user
or an independent assessment rather than inventing the next micro-slice forever.
A real blocker goes to the user/runner. Explicit recovery is allowed within a phase
without forcing a commit or claiming that unfinished work is complete.
Implementation stays in the parent; review/isolated ops assist, not implementation fanout.

## Current state is an index, not a journal

Use the task's existing scratch area; reuse evidence instead of duplicating it:
- `authority.md`: approved scope/exclusions, user decisions/permissions and sources.
  Only genuine user instructions change authority; an agent/report cannot grant it.
- `current.md` (`work_state`): phase/exit condition, original base/current candidate,
  current group/next action, links to unresolved issue and acceptance/gate indexes,
  still-valid check/review evidence. Replace obsolete frontier text, do not append
  every cycle's discoveries, commands, counters or completed test descriptions.
- issue/gate indexes retain ALL IDs/statuses, including superseded report lineage.
  Details/decisions/<id>.md hold reasoning, fix, verification and reopening conditions.
  Fixed-awaiting-verification is not closed; rejected findings retain their reasons.
- `resources.md`: CURRENT live/retained processes/stands/children, ownership, source,
  allowed operations and cleanup responsibility. Historical commands/check runs live
  in linked evidence, not an accumulating resource diary. Explicit none when none.
- producer results: immutable short/detail files per `result-contract.md`. Load only
  phase-relevant results. Verified decisions need not be re-proved after each reset.

No line/character quotas or extraction scripts. Compactness comes from separating
current navigation from issue details/history, not dropping facts or blockers.
Old state/results remain evidence; migrate a legacy large frontier once to a current
index with links. Never erase unresolved items to make it short.

## Persist then transition

Finish the phase, persist its outcome/check provenance/invalidations and next exit
condition. Record dirty/pre-existing work ownership if any. Reconcile actual child
status; finish/stop children before transition. Owned idle stands may remain with
explicit ownership. No forgotten background writer/test or duplicated resource.
Review and isolated ops may run concurrently WITHIN a phase on immutable inputs.

Write a new manifest under the task's `.scratch` directory:

```json
{
  "version": 2,
  "cycle": 1,
  "phase": "review",
  "transition": "phase-complete",
  "transition_reason": "Coherent purge increment committed; obtain independent source review now",
  "transition_evidence": ".scratch/RCL-XXX/work/decisions/purge-increment.md",
  "task": ".scratch/RCL-XXX/issues/NN-task.md",
  "authority": ".scratch/RCL-XXX/work/authority.md",
  "base_sha": "<original resolved SHA>",
  "head_sha": "<current resolved HEAD>",
  "branch": "<current feature branch>",
  "short_answers": [],
  "work_state": ".scratch/RCL-XXX/work/current.md",
  "resources": ".scratch/RCL-XXX/work/resources.md",
  "active_children": [],
  "next_action": "Launch independent review on the committed increment, not more implementation"
}
```

`phase` is the DESTINATION, not the completed phase. `short_answers` contains results
needed there; it may be empty before the first review. Do not invent a progress
report to satisfy a nonempty list. Increment cycle exactly once, preserving original
task/base/authority/branch. `transition: recovery` requires a concrete recorded reason
and saved state evidence; it is exceptional, not a workaround for per-test resets.

Call `ruclaw_next_cycle({"state_path":".scratch/.../cycles/0001.json"})` ALONE.
The tool checks refs/Git ancestry/identity, sequence, phase change (or recovery)
and declared absence of active children. It does NOT prove completion, scope,
permissions, resource ownership or acceptance. Those remain the executor's duty.

The next model request excludes earlier conversation, preserves system/tools and
subsequent messages, and points to `resume.md` + manifest. It does not instruct the
model to reload implement or every policy/result. This is not a new process/session,
compaction, timer, retry loop, transcript deletion or runner_finish. The active-branch
boundary survives resume/reload; other sessions/forks before it are unaffected.
A missing boundary produces STOP/reconcile recovery, never old-history reinjection.

v1 manifests are preserved historical data, not accepted for new transitions. Use
resume.md to migrate current navigation once; a persisted v1 boundary may restore
through that entry point. Do not rerun implementation/review to change formats.
If the tool is unavailable, explicitly start a fresh session from the saved compact
handoff after the previous writer is idle. Complete all required review/checks/
publication/status/cleanup and all children before final runner_finish.
