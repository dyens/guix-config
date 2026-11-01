---
name: code-review
description: "Review a RuClaw diff or GitLab MR for standards, requirements and correctness. Lightweight exact-ref review for small local changes; immutable bundles for broad, risky or parallel reviews."
---

# Code Review for RuClaw

Review **standards**, **requirement conformance**, and **correctness under
failures/concurrency**. Green tests or zero findings do not prove absence of defects.
Do not fix code, post comments or mutate remote state unless requested. Helper and
reference paths resolve from this skill directory, not the checkout.

## 1. Resolve scope and exact evidence

For a GitLab MR, read `../gitlab/SKILL.md` and retrieve metadata/refs with
`../gitlab/scripts/gitlab.py mr <MR-URL> --fetch`. Use the fetched MR head, not the
checked-out HEAD. For local/historical work, resolve the explicitly intended base
and head to immutable SHAs. A later sub-ticket may start at the prior feature tip;
a feature's target is not necessarily develop.

Record base/head, merge-base, commits, stat and all changed paths, including
renames/deletions/generated files. Initial coverage is the full `base...head`
increment; follow-up inspection is prior reviewed head..new head. If scope is empty,
inaccessible or ambiguous, stop with REVIEW INCONCLUSIVE. Uncommitted/untracked
changes are outside a committed review: disclose them, do not silently include or
commit them to obtain a snapshot.

Read the full originating spec/sub-ticket and applicable shared contracts. If no
standalone spec exists, the explicit user request/criteria define scope. Locate
sources via MR/branch/commits and selected docs, not guesses from old plans.
Missing required sources mean incomplete conformance verification. Use the profile's
area map for standards; check document currency and actual core wiring rather than
bulk-loading CLAUDE/workflow/glossary or treating ADR status as runtime proof.

## 2. Choose the evidence mode

**Lightweight exact-ref review** is allowed only when ALL hold:
- a small, cohesive local committed increment can be covered by one reviewer;
- all needed commit objects and related source are available locally;
- no parallel partitioning or independently assigned critical-chain pass is needed;
- no material security/tenant/identity, approval, durability/concurrency, migration,
  deployment, shared-contract or generated/binary artifact risk is involved.

Size alone does not establish low risk. Classify the full cumulative increment,
not only the latest fix delta. A GitLab MR, broad/risky change, uncertain impact,
unavailable exact-ref evidence or multi-reviewer work uses **bundled mode**.
Record the choice and rationale; never choose lightweight to evade review coverage
or independent-review gates. A single independent reviewer may use local exact refs;
lightweight does not authorize the implementation author to approve their own fix.

### Lightweight

No exported tree, lanes, coverage manifest or `results.json` is required. Inspect
all changed paths and related source through explicit SHAs in the source repository,
not mutable files. For example, with already resolved `base` and `head`:

```sh
git diff --no-ext-diff --no-textconv --find-renames "$base...$head" --
git show "$head:path/to/file"
```

Keep one short report with exact range/merge-base, all inspected paths, requirements,
findings, actual checks/gaps and verdict. Related callers/callees still matter.
A dirty checkout is not evidence for head. If risk expands or evidence cannot be
covered reliably, switch to bundled mode for the same original range and preserve
findings; no silent truncation or shortened coverage.

### Bundled

Read `references/bundled-review.md` before preparing/assigning work. It defines
immutable bundle creation, exhaustive batch assignment and results validation.
Use its exported head-tree, not the live checkout. All primary batches must be
covered; assignment integrity alone does not prove inspection.

In either mode, do not execute untrusted head-controlled scripts on the host.
Tests require an approved environment and the exact intended candidate.

## 3. Inspect behavior and invariants

For each changed area inspect all three axes:
1. Standards: applicable conventions, readable core business rules and real wiring,
   security/tenant/authz, compatibility, migrations, performance and testability.
   Do not demand unrelated DDD rewrites or report unproven smells.
2. Requirements: every criterion, partial/missing behavior, unintended scope.
3. Correctness: reachable negative paths, edge cases and explicit interleavings.

Risk questions where applicable:
- Ordered side effects and durable acceptance: fail between each pair; inspect real
  PG transaction/locking/closure semantics, not only fakes.
- Retry/recovery: same/new ID after partial failure, timeout, restart or reconnect;
  loss, duplication, typed unknown outcomes and user recovery.
- Queues: capacity, drain, cancellation, re-enqueue, ordering and accepted items.
- Approvals: full tool schema, current authority/revision, audit and provider history;
  editable-path permission or JSON kind alone is not validation.
- Producer → store → event/API → renderer → action → execution: silent/card-only/
  attachment-only results, stale versions and displayed/action payload equivalence.
- Cardinality/defaults: 0/1/many, forbidden items, multi-proposal selection,
  absent vs false/zero/empty and destructive fallback.
- UI errors: permanent forbidden/not-found/validation vs retryable network/conflict;
  visible reasons, retry/edit/remove and stale state.
- Generated/deployed artifacts: correct generator, compatibility, rollback and actual
  CI applicability, not static rendering presented as live deployment.

Follow affected callers/callees at exact head outside changed paths. Include an
end-to-end integration pass for cross-area chains, not only separate file reviews.
Each finding needs severity/axis, path or symbol, reachable scenario, evidence,
violated invariant, bounded impact and smallest fix. Record counterarguments and
checks not run; do not invent downstream security/payment harm.

## 4. Independence and follow-ups

Delegation is authorized when this review skill is invoked. Before launching or
consuming reviewer output, read `../implement/references/result-contract.md` for
producer-written short answers, linked detail files and separate resolutions. Read pi-subagents guidance
for the chosen branch and verify role policy/evidence access. Use a known supported
launch/resume recipe; do not reload full tool guides after every context transition
unless the operation is unknown, failed or the runtime/API changed. Direct launches
are sufficient unless orchestration is actually needed. An inaccessible scope is a gap, not “no findings”. Division of batches is not independence.
For critical delivery/storage, approval, tenant/security or concurrent transitions,
use bundled mode and an additional independent critical-chain pass without prior
findings. Reviewer count is risk-based, not a fixed fanout. The parent may be that
second look only if independent of the fix; record who covered what.

The parent verifies blockers at the exact snapshot. Cross-challenge only disputed
reachability/severity/fixes, not routinely every reviewer. Sequential fallback must
be disclosed and cannot be called independent when it is self-review. If required
independence is unavailable, preserve the gap. Assign exact SHAs, evidence mode,
repo or bundle/batches, full requirements, invariants and a unique writable result
directory under task scratch. Do not prime
an independent first pass with earlier findings.

For follow-ups read `references/follow-up.md` before carrying inspection forward.
Keep the original base, inspect delta plus affected invariants and update the
verdict. A new SHA alone does not require full re-review; uncertain/cross-cutting
impact does. Re-evaluate mode for each candidate; switching mode cannot erase gaps.

## 5. Verification and verdict

Use the profile's `testing.md` and actual scripts for current scopes/prerequisites.
Go needs goolm, UIs pnpm, Python service-local uv configuration. Review assertions,
not test presence. For critical chains seek failure injection, real PG replay/
negative paths, deterministic interleavings and generated-artifact parity.

For an implementation/fix candidate, require applicable cheap CI-preflight before
final review (including CI-configured security lint for changed Go tests); see
profile/testing.md. In review-only mode inspect available evidence and disclose gaps;
do not execute untrusted scripts or gain operational permissions from this rule.
Static review and parent-owned heavy verification may overlap on the same immutable
candidate with isolated resources. No live input edits; settle runs before fixes or
transitions. Pending mandatory checks cannot yield MERGE, even with no findings.
Use focused regressions during fixes and required expensive gates on the final
candidate. Reuse trustworthy same-snapshot/environment logs; for descendants use
`../implement/references/plan-cycle.md` input-equivalence rules. Never call
transferred results a fresh run. Rerun invalidated checks; preserve exact-head CI.
Missing cheap structural checks call for those checks, not ceremonial suite restarts.

In bundled mode, validate results as described in `references/bundled-review.md`
before synthesis. In lightweight mode, the report must account for every changed
path; no batch artifacts are required. Neither mode waives behavior/spec/test gates.

For an MR, use `../gitlab/scripts/gitlab.py ci <MR> --trace`. Require a successful
pipeline on reviewed head or a verified merged-result candidate tied to that head
and target. Inspect applicable/skipped/manual mandatory jobs. Recheck head/target
before publication; if moved, disclose historical coverage and inspect the delta.
Do not retry pipelines, change merge settings or push without authorization.

Verdicts:
- **DO NOT MERGE:** confirmed blockers or missing mandatory readiness gates.
- **REVIEW INCONCLUSIVE:** incomplete scope/spec/required verification.
- **MERGE:** all required coverage/readiness gates closed, not merely zero findings.

Produce `short.md` plus linked finding/coverage/check files under the result
contract. Preserve mode/range, inspected paths/batches, integration/independent
coverage, all gaps and fresh vs carried evidence. Return status and paths only.
The parent processes related issue groups and records decisions separately under
`../implement/references/plan-cycle.md`, never rewriting historical findings or
assuming the short verdict proves acceptance. Report real out-of-scope
defects separately; only the authorized executor edits debt/status files. Read-only
reviewers do not. Post only when asked, via `../gitlab/scripts/gitlab.py note <MR>
--file <short.md>`; ensure remote readers have usable evidence references (local
scratch paths alone are not remote evidence). Normally show the draft first unless
already authorized.
