# RuClaw implementation executor contract

The main `implement` executor reads this contract during initial onboarding and owns
the task end to end. Its safeguards continue to apply after a context transition;
use `resume.md` for recovery, not a ritual reread of this whole contract. Review/ops
children assist; the tmux runner only launches and waits.

## Input and authority

Record before editing:

- ticket/spec source and its full acceptance criteria;
- repository, cwd, branch, immutable `base_sha`;
- allowed scope (files/areas) and explicitly excluded work;
- required checks and any external prerequisites.

Use the RuClaw profile's area map for selective code/contract reading and its
`testing.md` for current test entry points. Read the full task and `git-workflow`
for corresponding operations. Do not bulk-load AGENTS/CLAUDE/workflow/glossary.
Documents and draft domain models may be stale or disconnected; distinguish
current behavior, approved intent and unresolved conflicts.
Do not overlap another executor's checkout or absorb unrelated changes into commits.
If requirements or scope must change, stop and ask the owner.

In this personal Pi workflow, the user grants default authority for local Docker/
Compose stands and dependencies owned by this task/ticket: build/pull images,
create/start/restart/stop/remove containers and their owned networks. No repeated
permission is needed for these actions, including an explicitly assigned ops child.
Verify ownership/isolation before changing existing resources. This does not permit
changes to shared/production/other people's resources, global prune, volume deletion
or persistent data resets without separate permission. More restrictive user
instructions override the default; preserve secrets, safe build contexts and the
stand's technical contracts. Cleanup is limited to your owned temporary resources.

## Design before implementation

Scale the design pass to the task. A small localized fix needs only a brief plan;
new modules or multi-component changes need an explicit architecture sketch before
implementation:

- module responsibilities, dependency direction and data flow;
- key types, function signatures and error handling;
- integration seams and how the behavior will be tested.

Put new/refactored business rules in core with readable domain/application code
and a real runtime connection. Check which modules are already migrated; do not
switch execution to draft/panic scenarios merely because they live in core.
Avoid mixed responsibilities, cyclic dependencies, unnecessary abstractions and
speculative extensibility.
Resolve unclear contracts before filling in implementations. A sketch in the plan
is sufficient; create signatures or temporary module stubs in the working tree only
when they help validate interfaces. Do not leave nonfunctional stubs, placeholder
behavior or scaffolding in the final code. If implementation exposes a design flaw,
revise the sketch and affected contracts before continuing; agree requirement
changes directly with the user.

Before building a substantial adapter around an unfamiliar SDK/protocol, identify
its riskiest assumptions and verify them with small executable contract tests
against the pinned version (for example numeric decoding, union selection, IDs,
retry/unknown-outcome behavior). Use task-relevant cases, not a mandatory broad
spike for every small change. Keep useful regressions; resolve contract surprises
before propagating assumptions through storage, transport and API layers.

## Cheap checks before expensive gates

Select existing checks from the actual diff, not a fixed whole-repo checklist.
Run applicable structural guards before the first review/deployment and rerun
those affected by fixes:

| Changed seam | Early check |
|---|---|
| Migrations | Latest migration vs required schema version, loader/upgrade guards and generated query parity |
| Tool registration | Registry/schema and policy group allow/deny coverage; typed unknown-outcome propagation |
| Checkpoints/DTOs | Old/missing/optional malformed fields, strict required-field validation and authority preservation |
| Multi-binding/story tests | Fixture identity uniqueness across cases, failure retention and test compilation |
| Build/deployment | Render/validate config, safe build context and launcher prerequisite checks |

Locate the project's authoritative guards and record exact commands in the check
plan. If no guard exists, inspect the invariant and add a focused regression when
useful; do not create a new framework for the checklist. Cheap checks complement,
not replace, behavioral, security and real integration tests.

## Useful comments only

Comments should explain non-obvious reasons, constraints or invariants, not narrate
what readable code already says. Use them for important design tradeoffs, complex
algorithms or concurrency, and workarounds for external bugs. For large, complex
functions, document the non-obvious flow only where it helps understanding.
First improve names and structure when a comment would merely compensate for
confusing code. Avoid redundant inline comments and boilerplate section labels.
Preserve required project/tool markers and necessary public API documentation.
During final review, remove newly added comments that provide no useful context.

## Verification safeguards

Follow the sequence in `../SKILL.md`; review coverage and follow-ups are defined
by `../../code-review/SKILL.md`, not a second procedure here.

- Prefer TDD where a clear seam exists. Use Go's `goolm` tag, UI pnpm and
  service-local uv/ruff/mypy configuration. Do not infer full Python coverage
  from strict tool settings; inspect the configured file scope.
- Never run shared-DB tests concurrently unless databases are isolated. Check
  current wrappers and resource ownership before they provision or remove anything.
  During fixes use focused regressions; reserve expensive integrated gates for
  the final candidate. Invalidate affected results, not every unrelated check.
- An inaccessible diff or unavailable independent review is a verification gap,
  not approval. Do not replace independent review with self-review or commission
  duplicate formal reviews merely because a child returned a result.
- Do not claim completion with required review/checks pending or blocking findings
  unresolved. A skipped required check blocks completion unless the user explicitly
  accepts that gap; record the waiver and risk. Pre-review work is a candidate,
  not reviewed evidence. Unexpected ancestry changes must not silently reset scope.

The main executor verifies findings and owns acceptance. Review/ops delegation is
limited to the accepted task scope; it does not grant extra operational authority.

## Reusing checks across integration

A new commit SHA does not alone require repeating a passing suite. The integrating
owner may carry results from a tested candidate to a merge/docs-only descendant
only after recording old/new SHAs, the complete tree diff, and equivalence of ALL
inputs relevant to each reused check: product/test/generated files, migrations,
dependency locks, build scripts/config/assets, toolchain/flags, environment and
external service/schema state. Include untracked inputs and commit-derived build
values; identical Go files alone are insufficient. Explain exclusions such as a
pure debt-note change. If equivalence is uncertain, rerun the affected check.

With proven equivalence, inspect the integration delta and run only checks that
it affects; do not schedule a fresh combined suite or rebuild merely because a
merge commit exists. Combining independently tested changes usually changes inputs:
run the required combined integration suite then. Review, acceptance and publication
gates remain mandatory. Exact-head CI required by project/MR policy still runs;
never claim transferred evidence was executed on the final SHA.

## Output evidence

The canonical evidence report contains branch, base/head SHAs, commits, changed
files, review outcome, unresolved findings, blockers/risks and these tables.
Do not return the full tables inline:

| Acceptance criterion | Evidence (test/code location) | Result |
|---|---|---|
| Each criterion verbatim | Concrete evidence | satisfied / unmet / unverified |

| Check | Exact command and cwd | Exit code | Result / skip reason |
|---|---|---|---|
| Each required check | Reproducible command | Number or not run | passed / failed / skipped |

Keep one canonical evidence/work index and update its gates and finding dispositions;
link separate decisions and producer detail files under result-contract.md.
Include snapshot/environment provenance for check logs; link details instead of
repeating large reports in chat. The integrating owner may reuse trustworthy results
for the same snapshot/environment or proven equivalent integration inputs under
the rules above, but must check integration effects and rerun invalidated checks.
Never describe reused results as fresh execution. Return a short handoff: exact
head, disposition, check outcome, evidence paths and blockers. Keep details/logs
in independently readable linked files, not duplicated into chat or one full report.
For review/ops results follow `result-contract.md` beside this contract: read the
short index, then the detail files for the chosen related group and acceptance
checks. Persist decisions separately; use `work-cycles.md` only for completed
workflow phase transitions or explicit recovery, not each finding/test. The current
index links detail/history instead of duplicating it. Resume through `resume.md`;
conversation is not the recovery database.

Distinguish verified facts from assumptions. Only the main executor may mark done,
after required review/checks and verified non-force push. In runner mode, wait for
all children and finish owned cleanup before calling runner_finish; it is a lifecycle
signal, not a second acceptance report or permission to waive a missing gate.
