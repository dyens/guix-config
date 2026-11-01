---
name: lite-implement
description: Implement an approved spec or external-review fix batch continuously, then obtain named independent review; experiment-local, no automatic publication.
disable-model-invocation: true
---
# Build the approved change

Read the request/input index and relevant detail files; record original fix-base
SHA and ownership of dirty work. A prepared comparison already fixes the base;
never replace it with partially implemented HEAD. Verify ancestry. Respect lab policy.

BEFORE product edits use /lite-acceptance's fixed recipe in
PI_RUCLAW_LAB_ROOT/prompts/lite-acceptance.md (read/call it yourself; do not ask the
user to re-enter a slash command). The independent evaluator prepares
behavioral cases on the original base, with explicit current user authority. Parent
inspects and seals the agreed suite and records its ORIGINAL SHA256 anchor before
implementation. Verify the seal/base/files before proceeding. Do not author or
weaken the evaluator's acceptance suite yourself; a justified change needs an
explicit scope decision/new seal while retaining old evidence.

Keep ALL approved IDs in the existing compact result index. Separate source
reasoning from actual behavior. Implement against the frozen observable contract,
not a list of test names or only changed paths. Confirm/reject original findings
against source; rejected items need evidence. Group related changes. Implement the requested batch with focused regression checks,
not repeated formal review and verification phases after every finding. Investigate
new dependencies only when required by a concrete issue. Do not audit the entire
original feature or copy fixes from the other benchmark branch/session.

Select actual test commands using shared profile/testing.md and current scripts:
focused cases first, relevant package/structural checks when stable. Expensive
integration checks only with owned approved resources; record real skips/blockers.
Do not repeat unchanged checks simply because a report/commit/context changed.
Inspect generated/config/CI changes through their real generator/consumer when touched.

Under explicit local-commit authority, commit the coherent candidate following Git/
changelog conventions. If commit permission is absent, ask; don't create a WIP
commit merely for tooling. Resolve the exact immutable candidate and use /lite-review
for the cumulative fix-base..candidate, original request, check-evidence file,
frozen acceptance seal and ORIGINAL anchor. Verify integrity first.
Set critical=true for tenant/auth, concurrent lifetime, send/retry/unknown-outcome or
other critical invariants. The source reviewer and independent behavioral evaluator must not see each other's
first findings. /lite-review runs both in one batch; the evaluator replaces the old
second source-only pass, not an additional third review.

Consume short indexes, then confirmed finding/coverage/check details; independently
check reachability before fixing. Correct confirmed defects, run affected regressions
and obtain a delta/affected-invariant follow-up, carrying unchanged coverage honestly.
No full re-audit merely for a new SHA. If evidence is inaccessible report the gap.

Reconcile EVERY frozen criterion/case, not just evaluator-selected candidate tests.
Fix confirmed counterexamples without editing acceptance assertions/tiers. Failed,
skipped or blocked requirement cases mean requirement acceptance is NOT met; source
review cannot override that. Missing agreed delivery infrastructure is reported
separately, not a reason to invent a new E2E platform or repeatedly broaden scope.

Final result has TWO separate verdicts: requirement acceptance against the frozen
suite, and delivery readiness (CI/deployed E2E/merged-result). Link every ID/case,
source reasoning, exact checks/reviews and remaining gates. Neither source review
nor a green subset proves requirement acceptance or delivery readiness. No push/MR/deployment in this experiment without separate permission.
