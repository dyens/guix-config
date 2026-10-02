---
name: code-review
description: "Review a RuClaw local diff or GitLab MR against project standards, its full spec, and correctness invariants. Requires complete primary-batch coverage and explicit verification gaps."
---

# Code Review for RuClaw

Review on three axes: **standards**, **spec conformance**, and **correctness under failures/concurrency**. Never equate a green test suite or a completed review with absence of defects. Do not fix code or post comments unless requested.

All helper paths below are relative to this skill directory. Resolve them against the loaded SKILL.md, not the checkout.

## 1. Freeze the evidence

For a GitLab MR, first read the sibling `../gitlab/SKILL.md` and run:

```bash
../gitlab/scripts/gitlab.py mr <MR-URL> --fetch
```

Use the returned target/base SHA and fetched MR head ref. Never blindly review HEAD:

- checked-out local feature: explicit review-base and HEAD;
- another branch: explicit branch/ref;
- MR: fetched MR ref;
- historical review/note: the exact historical commit, even if the MR has moved;
- later sub-ticket: previous feature tip if reviewing only that increment.

Record exact base/head SHAs, merge-base, commits, stat and changed paths. Always use `base...head`. Confirm the intended target; a feature target is not necessarily develop. If the diff is empty or the requested snapshot is inaccessible, stop with REVIEW INCONCLUSIVE.

Read the **full originating spec/sub-ticket**, MR description and relevant project/package standards. Infer spec from branch, commits, `docs/specs/` and `.scratch/` if necessary. A description or summary is not equivalent to the full spec: if it is unavailable, explicitly mark spec verification incomplete; do not claim full conformance.

Prepare a new exact-snapshot bundle:

```bash
scripts/prepare-review-bundle.sh <base> <head> .scratch/reviews/<id>/<head-short>
scripts/prepare-review-lanes.sh .scratch/reviews/<id>/<head-short>
```

Use a fresh directory for every run, including repeated review of the same SHA. Do not reuse results after changing evidence. The bundle includes metadata, diff, stat, commits and a detached head-tree. Inspect that snapshot, not the live working tree. Do not execute untrusted head-controlled scripts on the host; use an approved isolated test environment.

## 2. Enforce complete primary coverage

`prepare-review-lanes.sh` partitions all changed paths into topic batches. Default topics are approval, chat runtime, A2UI, chat UI, contracts/artifacts, ops/docs, backend, frontend and services. Empty topics are omitted. Rules assign the first match as primary owner, while supplementary checks may overlap.

Defaults: at most 12 files, 800 patch lines or 64 KiB patch bytes per batch. A single oversized file is explicitly flagged and requires a dedicated semantic pass; do not silently truncate or skip generated artifacts. Read relevant source at head-tree when diff context is insufficient.

Outputs:

- `lanes/<batch>/{files.txt,diff.patch,diff-u80.patch,brief.md}`;
- `coverage.json`: exact snapshot, primary assignment and evidence hashes;
- `results.template.json`: pending status for every primary batch;
- `unassigned.txt`: unknown paths.

Unknown paths **block preparation**. Inspect them and supply task-specific ordered rules with `--rules <json>`; the JSON is a list of `{ "lane": "name", "pattern": "regex", "brief": "risk-focused instructions" }`. Custom rules replace defaults. Do not add an unexplained catch-all to hide missing scope. Include every path, including deletions, fixtures, docs, migrations and build config.

Validate before dispatch:

```bash
scripts/prepare-review-lanes.sh <bundle> --validate
```

Coverage PASS only proves assignment integrity, not inspection. Never substitute agent count for coverage. For a broad MR, review all batches even after finding blockers.

## 3. Review batches and end-to-end chains

For each batch review all three axes:

1. **Standards:** cite documented rules; check security, tenant/authz, compatibility, data loss, migrations, performance and testability. Report smells only if concrete and actionable.
2. **Spec:** compare to the full requirements and acceptance criteria; identify missing/partial behavior, wrong implementation and unintended scope.
3. **Correctness:** identify invariants and try to break them with reachable negative paths, edge cases and interleavings.

Mandatory risk questions where applicable:

- **Delivery/storage:** list ordered side effects and the durable acceptance point. Inject a failure between each pair. Can terminal/closed state precede accepted work? Check real PG transaction/locking/closed-state semantics, not only fake stores.
- **Idempotency/recovery:** retry with both the same and a new ID after partial failure, timeout, reconnect and restart. Can the user recover without losing accepted work or duplicating effects?
- **Queues/concurrency:** full capacity, terminal handoff, a new run/action during drain, cancellation and re-enqueue. Preserve accepted items, reservations and ordering. Write an explicit interleaving, not just “possible race”.
- **Approval/schema:** editable-path permission and JSON kind are not full schema validation. Check enum, pattern, ranges and nested constraints against the authoritative tool schema before consuming the decision; then current policy/agent authority, revision, audit and provider history.
- **Producer/consumer:** follow source → persistence → event/API → renderer → action → execution. Verify silent/card-only/attachment-only results, stale versions and displayed-result/action-payload equivalence.
- **Branch/cardinality:** compare 0/1/many paths. Special-case single items must preserve the general forbidden/payable predicate; multi-proposal previews must correspond to the selected action.
- **Frontend errors:** distinguish retryable conflict/network failures from permanent FORBIDDEN/NOT_FOUND/validation outcomes; check visible reasons, retry, edit/remove and stale state.
- **Optional values:** absent versus false/0/empty; nil/off defaults; destructive fallback behavior.
- **Artifacts/readiness:** authoritative generation, deployment compatibility, migration/rollback and actual CI applicability.

A reviewer must follow related callers/callees outside its primary paths at the exact head. “Review only the diff” limits the scope of findings, not the evidence needed to prove them.

Additionally assign an **integration pass** over critical cross-batch chains. For an A2UI/chat MR this includes acceptance → store → closure → queue/drain, background result → publication, amendment → schema/policy → dispatch, and preview → action. This supplements primary coverage, not replaces it.

Report each finding as: severity, axis, path/symbol, reachable scenario, concrete evidence, violated invariant, bounded impact and smallest fix. Do not claim downstream payment/security harm unless demonstrated. Record checks not run and unresolved counterarguments.

## 4. Independent challenge

Delegation is authorized by this skill when invoked for review. If needed, call `subagents_enable`; read the pi-subagents skill before launching work. Verify reviewers can inspect the exact bundle. A lane that cannot read evidence is an infrastructure gap, never “no findings”. Direct sequential review is the fallback and must be disclosed.

Partitioning batches is division of work, **not independent review**. For critical delivery/storage, approval, tenant/security or concurrent state transitions:

1. Have a second reviewer independently inspect the same critical chain and invariants **without first seeing the first reviewer's findings**.
2. Only then exchange findings and counterexamples.
3. Ask each reviewer to falsify reachability, check existing guards and narrow unsupported impact.
4. Parent personally verifies retained blocking chains at the exact snapshot.

If resources/tools prevent the independent pass, record that gap and do not label the result independently reviewed. A different model is optional; a fresh evidence-based pass is essential. Never silently shorten coverage to fit the parallelism budget.

Subagent handoff must include exact SHAs, bundle and batch paths, full spec, relevant standards, required invariants, evidence-access requirements and expected report path. Do not provide earlier findings in the independent first-pass handoff.

## 5. Tests and completion gate

Review existing test assertions for behavior, not just presence. For critical chains request or run in an approved environment:

- failure injection between state change, prepare and durable accept;
- real PG negative-path/replay tests;
- deterministic queue/drain interleaving tests (use barriers, not sleeps);
- permanent versus retryable frontend errors;
- card-only background and 0/1/many/forbidden-item/multi-proposal cases;
- authoritative OpenAPI/client/fixture regeneration and a clean artifact diff.

Use `GOFLAGS=-tags=goolm` for Go; combine explicit tags with goolm. Use pnpm for UI and uv for services per project rules. Do not assert checks passed if only static inspection ran.

Copy `results.template.json` to `results.json`. For every batch supply:

```json
{
  "chat-runtime-01": {
    "status": "reviewed",
    "report": "reports/chat-runtime-01.md"
  },
  "approval-01": {
    "status": "gap",
    "report": "reports/approval-01.md",
    "reason": "Exact evidence unavailable; requires another pass"
  }
}
```

The example is illustrative; use exactly the batch IDs in your manifest. Each report must state inspected scope, invariants, findings or no findings, and verification gaps. `reviewed` means inspection completed, **not** defect-free. Pending/missing results block completion. `gap` requires a reason and yields REVIEW INCONCLUSIVE.

```bash
scripts/prepare-review-lanes.sh <bundle> --validate --results <bundle>/results.json
```

Run before synthesis/publication. Mechanical validation cannot prove that a report is truthful; parent checks reports against their batch evidence. Independently record integration/second-pass results and runtime/artifact/spec gaps; batch completion does not close these gates.

For an MR, inspect CI with the sibling GitLab helper:

```bash
../gitlab/scripts/gitlab.py ci <MR-URL> --trace
```

Require a successful pipeline on the exact reviewed head, or a verified merged-result candidate tied to that head and target. Check job applicability, skipped/manual mandatory jobs and feature-target workflow rules. A successful old pipeline, missing pipeline or unrelated integration stand is not this gate. Recheck the MR head/target tuple before publication; if it moved, describe the historical scope and review the delta before a current merge recommendation. Do not change GitLab merge settings or retry/push without authorization.

## 6. Synthesis and output

Deduplicate root causes, verify evidence, normalize severity and preserve concrete impact. Do not invent findings to fill coverage. Record real out-of-scope issues in `docs/superpowers/debt.md` per its format; known/deferred scope is not a newly discovered defect.

Verdict:

- **DO NOT MERGE:** confirmed blockers or missing mandatory readiness gates;
- **REVIEW INCONCLUSIVE:** incomplete inspection/spec/required verification;
- **MERGE:** only when required coverage and readiness gates are closed, not merely zero findings.

Return a concise summary with:

- blockers and non-blockers: scenario, paths, impact, fix;
- exact range, merge-base and bundle;
- primary coverage paths/batches, oversized-file treatment;
- integration chains and independent passes completed/not completed;
- actual tests/generation/CI run and outstanding gaps;
- previous findings fixed/open, separating delta checks from fresh full review.

Post only when asked, via `../gitlab/scripts/gitlab.py note <MR> --file <review.md>`. Normally show the draft unless explicitly authorized to post. Do not claim complete coverage from partial or infrastructure-failed reviews.
