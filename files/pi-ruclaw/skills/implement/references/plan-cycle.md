# Default implementation safeguards (plan-cycle v2)

This is not a second phase engine. Keep one short plan and linked results. The
old executor-contract/work-cycles/resume references remain for explicit legacy
recovery, not default onboarding. Technical runtime details: the shared
pi-plan-cycle README (source: files/pi-extensions/plan-cycle/README.md).

## Scope and Git

- One ticket/feature branch/MR unless the user approved an experiment/worktree.
  One product writer per checkout. Never absorb pre-existing work, reset/stash/clean
  another writer's files, switch their branch or change their refs.
- Resolve and record immutable original base before edits. For a fresh ticket use
  the agreed resolved target; for a later subtask use the previous task's verified
  endpoint only when it is the intended ancestor. After squash/merge or a new target,
  resolve the approved new task base; preserve old bases/report links as history,
  not as a fictitious cumulative ancestor. Preserve bases on SAME-task recovery.
  Ambiguous history is a blocker.
- Read the task and criteria fully before checkpoint 0. Code shows current behavior,
  not approved intent; docs may be stale. Resolve material conflicts by area, not
  by loading the whole archive or automatically preserving bugs.
- Read git-workflow and relevant Git/changelog documents before operations. The
  standing USER permission in implement/SKILL.md authorizes ordinary local commits
  of task-owned changes on the agreed task branch, unless explicitly restricted;
  do not ask again for the review candidate or each fix. Inspect index/diff and stage
  only owned paths/hunks. It does not authorize amend/history rewriting, commits on
  develop/main/release, branch switching or remote publication. Those require separate
  authority; conventions and task plans do not grant it. No agent co-author trailers.

## Task and context lifecycle

Continue the same plan for its fixes/reviews/integration. At an agreed endpoint,
new standalone work belongs in a fresh session with its own intake/checkpoint/plan.
Do not reuse an active plan merely because start refuses, or carry the old branch's
scope/base through unrelated branches. If uncertain whether this is continuation,
resolve scope before edits. This is not an automatic session switch or gate waiver.

Settle children/operations and make the previous writer idle before handoff. Record
user-sourced scope/permissions, original and current refs, dirty ownership, criteria,
open findings/gates, resource ownership and next action; link immutable past evidence.
Standing implement defaults apply to a new authorized implementation task too;
additional push/deploy/history-changing authority does not transfer from an old task.
`/plan-cycle stop` restores ordinary history; use a fresh session, not stop/start,
for a clean context. Do not disable safeguards or erase unresolved work to save tokens.

Keep plan.md an index of the CURRENT task: short step outcomes and evidence links.
Move investigation logs, commands, input manifests and dispositions to linked files;
retain their provenance and unresolved IDs without copying them into every step.

## Design and checks

Scale design to the task: a brief small-fix plan or a multi-component architecture
sketch with ownership, dependency direction, data flow, interfaces/errors and test
boundaries. Prefer readable core rules with real runtime wiring; no unrelated DDD
rewrite or draft/panic paths. Use executable pinned-SDK/protocol contract tests for
concrete risky assumptions before propagating them through adapters.

Use actual test entry points from profile/testing.md/current scripts. Check cheap
structural invariants where relevant (migrations/generated parity, registries/policy,
DTO compatibility, fixture identity, safe builds/config render) before expensive
execution. Prefer deterministic negative and real producer/consumer boundary cases,
not just positive mocks. Go uses goolm, UI pnpm, Python service-local uv settings.

Use LSP navigation when it helps understand a symbol or assess change impact:
definition/references for declarations and semantic uses, hover for types/docs,
symbols for file structure. Supplement it with text search for config/reflection,
generated artifacts and external consumers. Navigation is discovery, not exact-ref
review evidence unless its source/config matches the reviewed candidate.
LSP diagnostics are optional quick feedback, not a mandatory post-edit gate. Do not
duplicate a successful compiler/typecheck on the same relevant inputs/configuration
unless LSP adds diagnostics or helps investigate a discrepancy. If checking, finish
related edits first and batch relevant saved files; never race checks with edits.
Do not retry a known unavailable server until the environment changes. Stale/absent
diagnostics do not prove correctness or replace required tests/lint/review.

For a confirmed defect, enumerate supported variants of the violated invariant
before patching: real instance vs type, producer/consumer representations, cardinality,
negative cases and trust boundaries as applicable. Add deterministic regressions for
the class; do not extrapolate unrelated requirements. A repeated same-invariant finding
calls for design/contract reassessment before another fix loop.

During fixes run affected regressions. Reuse earlier check evidence only with
recorded old/new SHA and equivalence of ALL relevant inputs: source/tests/generated
files, locks/config/build scripts/assets/toolchain/flags/env and external schema/
services, including untracked and commit-derived inputs. If uncertain, rerun. Never
call carried evidence a fresh run; exact-head CI remains separate when required.

Keep one linked check index (Markdown is enough), not a second phase engine:
`check | candidate SHA/tree | scope | toolchain/config/env/resources | command/cwd |
exit + skips | evidence`. For each descendant list delta, semantic blast radius,
invalidated checks and carried checks with old/new identities and input-equivalence
reason. Changed-path equality alone is insufficient. Use Git trees/blobs and targeted
manifests to establish relevant input identity; no ceremonial whole-repository copy
or hash scan unless needed for the actual build/test boundary. Unknown inputs mean
rerun or an explicit gap. Never reuse an old test result as exact-head CI.

## Docker and resources

Standing USER permission for implement permits local Docker/Compose for isolated
task-owned stands/dependencies: build/pull images, create/start/restart/stop/remove own
containers and their own networks. Do not ask again for operations within these bounds.
Verify ownership/isolation before changing existing resources; unclear ownership is
not permission to touch them. More restrictive task instructions always win. Record
the default authority and explicitly pass bounds to ops children.
This does NOT allow shared/production changes, global prune, volume deletion or
persistent-data resets without separate permission. Do not infer host firewall,
privileged or security-bypass authority from a generic Docker grant.

Inspect provisioning wrappers BEFORE running them: fixed-name cleanup, shared DBs,
unsafe mounts and broad build contexts may violate ownership. No parallel shared-DB
tests without isolation. Keep secrets out of logs/build contexts. Record current
live resources/ownership/cleanup in a linked result, and settle children before a
context transition. A worktree is not a Docker/network/credentials sandbox.

## Review and evidence

Default formal review follows coherent implementation, focused regressions and
applicable cheap CI-preflight, not every component or all expensive verification.
Commit under standing implement permission unless restricted (no repeated consent
round), then launch fresh ruclaw-plan-reviewer with explicit
task/base/head/authority/evidence/result directory. Parent-owned heavy checks may run
alongside static review on the same immutable candidate with isolated resources.
No implementation workers. Ops is optional for bounded authorized heavy checks.
Child roles do not delegate.

Keep the checkout/input set fixed until readers/tests finish or stop them before
fixing; an exact Git review does not make a live test checkout immutable. Separately
frozen test inputs require verified candidate identity and safe build context. Record
old-candidate results honestly and invalidate affected evidence after fixes. Finish
all runs before transitions; join review + required checks before final acceptance.
Do not prime the independent first source pass with peer/builder verdicts; execution
logs may be checked afterward as provenance, not proof of source correctness.

Use direct single-reviewer launch/resume when sufficient; workflow/mission machinery
is not a mandatory extra ceremony. Pass role, fresh first-pass/exact refs, criteria,
authority, evidence paths, unique result directory and output:false/outputMode:inline.
For follow-ups include prior report/head, full delta and affected invariants. Verify
resolved role policy/access before launch. Use the known supported tool recipe;
load full tool guides only for unknown operations, errors or a changed runtime/API,
not routinely after every context transition. Re-read applicable Git/policy sources
when changed, unavailable in context or needed to resolve an operation; do not replace
permission checks with remembered blanket authority.

An inaccessible scope or unavailable independent reviewer is a gap, not zero defects.
Every confirmed blocker must be fixed/reviewed or remain explicit. Keep dispositions
separate from immutable reports. For current tasks plan.md links decisions/reports;
there is no required current.md/phase manifest database. Follow-ups cover delta and
affected invariants, not ritual full rereviews. Scope/security/concurrency redesign
may require broader scrutiny when impact is uncertain.

The final result links all criteria and findings, exact base/head/commits, checks
with command/cwd/exit/evidence, actual review run IDs, publication outcome, remaining
gates and owned cleanup. No line quotas; keep details out of the short plan/chat.
Required skips/blockers mean incomplete requirements unless the user explicitly
changes the agreed endpoint. Even an authorized source-only endpoint does not prove
live execution, delivery readiness or production acceptance.
