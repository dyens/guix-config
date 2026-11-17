# Structured tasks + bounded step context

Opt-in extension for Pi 0.87.1; default in pi-ruclaw. No new dependencies, Git
writes, background model calls or product edits by the extension.

```sh
pi --extension ~/vms/guix-config/files/pi-extensions/plan-cycle/index.ts
# resume with the same extension; Guix installs ~/.config/pi-plan-cycle/
```

## Agent workflow

After reading the original task, criteria, authority and relevant inputs, before
product edits, call ALONE:

```json
{"plan_path":".scratch/my-task/plan.md","context":"Immutable original base/branch, scope, permissions and required gates","steps":[{"title":"Implement behavior"},{"title":"Test behavior","needs":[1]},{"title":"Independent review and agreed delivery"}]}
```

Tool: **task_plan**. It saves checkpoint 0 (excluding its pending call), persists
structured tasks, activates the first step and exports a human-readable Markdown
plan. No manual start/next/INPROGRESS edits. IDs start at 1; optional instruction
adds bounded step-specific detail, needs names earlier steps whose results are inputs.

Execute a coherent increment, finish tools/children, then call **task_complete**
ALONE with id, short result, optional checks, handoff and notes. This saves the
result, marks the step done, activates the next and creates a clean context boundary
in one operation. Even the final step gets a boundary; repeated completion is rejected.
No report file is required. Git HEAD/dirty metadata is observed automatically where
available; it is not an owned-path inventory, test result or proof of acceptance.

- **task_get(id)** reads ONE archived step when needed, not routinely at startup.
- **task_block(id, reason)** saves partial work/blocker without resetting context.
- **task_replan(reason, steps, notes?)** revises ALL remaining steps in the same
  context. Existing unfinished IDs are stable; omitted unfinished steps are cancelled
  with a reason; new steps get fresh IDs. Completed/cancelled history is immutable.
  Reordering respects earlier-step dependencies. It can add review fixes after all
  steps finish. User scope/permissions/gates are not changed by a technical replan.
- notes REPLACES bounded living decisions/open findings/gates/resources. Preserve
  unresolved items, discard obsolete detail; do not append a diary.

Results/checks/handoff have bounded schemas (1000/1200/1500 characters); notes 4000,
contract 6000, at most 1000 archived steps. Long logs/substantial findings may use
linked files; ordinary successful steps do not create report packages. Required
checks and independent final review are still agent responsibilities.

## Human status — no LLM

```text
/task_get_status
Tasks: 10/300. Plan: /absolute/path/to/plan.md
```

A registered user command, NOT an LLM tool. It calls no model and appends no
conversation or task state. Blocked adds `(blocked)`. Counters exclude cancelled
steps and do not certify task acceptance. `/plan-cycle stop` disables filtering;
next request sees ordinary history, so stop/start is not a clean reset.

## Storage and generated plan

Branch-local session custom entries are authoritative, not plan.md. Extension
exports the complete archive to that file for humans. Editing/deleting it does not
replan execution. Export uses a queued atomic rename; export failure is reported
without losing committed session state. The next task update retries export.
The full generated file is never automatically fed to the model.

Boundary entries store tasks and snapshot together in ONE plan-cycle-state-v2
entry, with an explicit structured workflow marker. In-step block/replan updates
use plan-cycle-tasks-v1; native read provenance uses plan-cycle-read-v1.
Existing Markdown v2 sessions remain supported with their old plan_cycle_start /
plan_cycle_next and /plan-cycle commands; next refuses structured tasks. No silent
migration or mixing with legacy work-cycles/v1. Resume work-cycles only with explicit
pi-ruclaw --legacy-cycles; legacy v1 requires an agreed handoff/new checkpoint.

## Bounded model context

Each boundary carries:
- original checkpoint 0, invalidating old read contents when changed/untracked;
- newer user messages verbatim and exact completed ask_user_question pairs;
- fixed task contract, bounded living notes, current step, next three titles;
- previous completed result plus explicitly needed dependency results (max 8 needs);
- up to 8 small verified native text read pairs, total <=24 KiB, from prior steps.

The rest of completed plans/results, tool outputs and reasoning stays in transcript,
not model context. Thus a 300-step archive is not a 300-result prompt. No task_get_all.

Read fingerprints (realpath + SHA256) are tracked before/after native read, including
intake. A race, retargeted symlink, missing file or unknown provenance invalidates
reuse. Carried reads are latest per path/range, text-only, exclude generated plan,
failed reads, sibling calls and assistant narration. Canonical context edits/omissions
are respected; raw history is not resurrected. The model reads missing/stale sources
only when useful; there is no ceremonial reread before each automatic status change.

Snapshot, plan and read decisions stay frozen WITHIN a step, including reload.
New read/edit/write results extend the tail normally, preserving prefix cache.
Disk changes are checked again at the next boundary, not on every model request.
This is not a filesystem snapshot/watch, sandbox or freshness guarantee against
external edits after checking. Bash/search output and checkpoint reasoning may stale.

Questionnaire call/results remain exact and ordered, including cancellation/error/
partial/custom answers and notes. Only those calls survive from prior assistant
messages, not sibling work/thinking. Cancellation, unanswered options or recommendations
are not permission. Later user corrections override agent-written summaries.

## Recovery and safety

Reload/reopen and tree branching use ONLY active-branch session state. An incomplete
questionnaire pair, lost checkpoint/boundary, corrupt state, unknown context transform
or compaction after checkpoint produces explicit STOP and blocks tools, never silent
restoration of unfiltered old history. Canonical context edits remain authoritative.
Compaction is cancelled while enabled; split oversized steps or use a fresh-session
handoff. Checkpoint 0 must itself fit. New standalone tasks use a fresh session,
not an ever-growing old task scope/base. Settle old writers/children first.

Transitions require an isolated call, stable session and cancellation checks.
Task state + boundary commit as one session entry before recoverable view export.
No general trustworthy background-job registry is available: parent must settle all
children/tools. Extension does not validate claimed test success, gate satisfaction,
resource ownership or permissions. Task counts/DONE never authorize push/deploy.

## Tests without models

```sh
node --import ./files/pi-ruclaw/tests/peers.mjs --test \
  files/pi-extensions/tests/plan-cycle.test.ts files/pi-extensions/tests/tasks.test.ts
```

Real SessionManager/projection, reopen/branch, native loader/runner, legacy support,
questionnaire preservation, stable prefixes, bounded read carry, atomic completion,
blocking/replan and human status without model calls. No real reviewer/models/stands.
