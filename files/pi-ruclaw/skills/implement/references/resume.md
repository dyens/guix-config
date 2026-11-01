# Resume an existing RuClaw task — not implement onboarding

Use this entry point after a phase transition or a user-requested handoff. Do NOT
reload implement, executor-contract, result-contract, work-cycles and testing as a
startup ritual. System/personal instructions still apply. Read a specific policy
reference only for an operation or uncertainty that actually needs it.

## Restore once

Read the supplied handoff/manifest and compact current work index. Preserve the
ORIGINAL task base, branch, approved scope/permissions and unresolved gates. Check
actual HEAD, dirty/staged work ownership and live resources/child status. No reset,
stash, clean, rebase, new branch, relaunch or deletion just to make recovery easier.
An active writer must stop before another executor takes over the checkout.

The current index contains only: destination phase + exit condition, original base
and candidate, current issue-group links, unresolved issue/gate index, still-valid
check/review evidence links and one next action. Completed reasoning, chronological
progress, test inventories and navigation belong in linked detail files, not here.
Resource state lists CURRENT live/retained resources and ownership, not the history
of every test command. Keep all old evidence, but do not reload it by default.

Trust a recorded verified decision only with its provenance and unchanged inputs;
a context transition alone does not invalidate it. Do not rediscover closed issues
or rerun unchanged checks merely to regain confidence. Uncertainty is a specific
question to resolve, not a trigger for a new whole-system audit.

## Execute the destination phase

- **implement:** complete a coherent, independently reviewable increment and its
  focused checks. Under existing Git authority, commit that increment selectively
  and move to review; do NOT wait for every criterion of a large task. No speculative
  test/audit expansion. A recurring cross-cutting flaw needs a design decision or
  independent assessment, not endless new micro-slices. Ask if scope must change.
- **review:** FIRST call `subagents_enable` if needed, then use `subagent` to launch
  fresh `ruclaw-reviewer` on exact committed SHAs. Verify resolved role policy/evidence access; use code-review for
  actual review mechanics. Review all cumulative changed scope; state incomplete
  overall criteria explicitly. Interim source review is not task/MR acceptance.
  Multi-file reviewer/ops results require child output:false/outputMode:inline, not
  a bound single receipt path; final inline completion is only status/paths.
  A pre-existing complete single-output review may be consumed via a parent-authored
  navigation index with truthful provenance, not repeated for format alone.
  Do not return to new implementation without obtaining the review or reporting
  why it is unavailable. Self-review is never independent review.
- **fix:** resolve confirmed findings with focused regressions; persist dispositions,
  commit under authority, then obtain delta/affected-invariant review. Do not repeat
  the unchanged whole inspection or start unrelated investigations.
- **verify:** run final required gates on the approved candidate. Use `ruclaw-ops`
  for isolated heavy checks/preparation when useful; review and ops may overlap on
  immutable inputs with nonoverlapping resources. Preserve failed/pending/skipped
  gates; rerun invalidated inputs, not every historical test. A new defect goes to
  fix with evidence, not a silent scope expansion.
- **publish:** reconcile ALL issue/gate dispositions and coverage; non-force push
  the reviewed head, verify origin, then status/owned cleanup and runner_finish.
  Pending gates or required independence prevent done. Wait for all children.

Stay in the phase until its exit condition or a real blocker. Do not call
ruclaw_next_cycle after each finding/test. Read only the result short answers and
detail files needed in THIS phase. Producers write short/detail files directly;
the parent records decisions separately, never rewriting historical findings.

## Legacy/large state and interrupted sessions

An existing v1 manifest or large state.md is navigation/evidence, NOT an instruction
to read all history. Start from the user's compact handoff and Git. Create one
current.md index linking the existing issue/gate/decision evidence; preserve every
unresolved item in its index, but do not copy its reasoning into the frontier.
Keep the old files unchanged as historical references. Update current live resource
inventory separately. Consult individual legacy sections only for a concrete gap.

v2 transitions require phase/reason/evidence. Read work-cycles.md only when preparing
that transition or migrating the manifest once. Increment the existing cycle number
when resuming the same session; keep task/base/authority/branch. In a fresh session,
recover the original values from the handoff rather than choosing a new base.
If the boundary is missing or ownership/authority/history is uncertain, STOP and
reconcile with the user. Do not infer completion or start duplicate work.
