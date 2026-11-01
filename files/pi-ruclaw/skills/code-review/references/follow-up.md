# Follow-up review after fixes

Read this reference when reviewing a descendant of an already reviewed candidate,
not for an initial review. Paths to helpers resolve from the code-review skill
root. The initial-review gates and final verdict remain in `../SKILL.md`.

The first pass covers the complete immutable `base...head` range. For a descendant
candidate, retain that original base for cumulative scope; inspect
`previous_reviewed_head..new_head` plus affected callers/callees, contracts, tests
and invariants. Re-evaluate evidence mode against the full cumulative increment,
not only a small fix delta. In bundled mode prepare a new bundle; lightweight mode
uses exact local refs and a new short/detail result directory, without lanes or
batch results.json. Previous candidate results stay immutable.
Do not re-read unchanged unrelated scope just because HEAD changed. New HEAD
requires updated approval, not automatic full re-review.

Before carrying evidence forward, the parent must:

- verify the same original base and that the prior reviewed head is an ancestor;
- record the prior report, its evidence mode, bundle when applicable, and exact old/new SHAs;
- enumerate all delta paths, including deletions/renames/generated/config changes;
- map every delta and its semantic blast radius to reviewed paths/invariants
  (and current primary batches in bundled mode);
- verify unchanged path blobs and relevant dependencies/contracts at the new head;
- check each prior finding's disposition and review new code and regression assertions.

In bundled mode, generated batch briefs describe initial full coverage. For follow-ups, explicitly
include this delta-review protocol in reviewer assignments; do not let a generic
"review full spec/all paths" brief trigger repeated inspection of verified unchanged
scope. Reviewers still need the original requirements and exact new-head context.

In either mode distinguish fresh delta inspection from carried inspection, with
prior report references, verified unchanged paths, affected invariants and gaps.
Lightweight mode records this in the new result's short index and coverage file;
link earlier results and retain open IDs/dispositions. No batch reports or
`results.json` are required. In bundled mode cover each current batch; IDs may
change, so map by paths/scope, not matching IDs. `reviewed` means coverage is
justified by the evidence chain, not that every line was re-read. Manifest
validation checks report presence/hashes, not carry-forward validity; parent owns it.
Never carry test execution forward as if it ran on the new head. Use the parent's
linked check index to distinguish candidate/scope/environment/command/result/evidence,
invalidated checks and justified carry-forward; do not reproduce a full historical
test journal in every report. Parent owns input-equivalence and actual execution;
a static reviewer evaluates assertion validity and gaps, not a claim of fresh tests.

Return to full review of the affected scope when architecture, shared contracts,
security boundaries or concurrency design materially change, or impact cannot be
bounded. Re-review the whole range only when the change is cross-cutting or prior
coverage is unreliable/missing; a changed SHA alone is not a trigger. For each
confirmed defect identify the violated invariant and supported variants, not just
the reported example. Check regression assertions across relevant representations,
real instance/type identities, 0/1/many and negative/trust-boundary cases. Keep this
bounded to the task; do not invent unrelated acceptance requirements. If successive
fixes keep exposing the same boundary flaw, pause for a focused design/contract test
before another patch-only cycle. Never waive real blockers to stop a cycle.

A follow-up is not a reason to finish every expensive suite before source inspection.
After applicable cheap CI-preflight and focused regressions, review can overlap
parent-owned heavy checks on the same fixed candidate with isolated resources. No
live input edits; settle runs before fixes/transitions, and record the actual reviewed
and tested revisions separately. Source PASS with pending mandatory checks is not
MERGE/readiness approval. A separate new task after an agreed endpoint needs its own
session/intake/base, linking prior findings/gates rather than silently carrying an old
plan and cumulative range through unrelated branches.
