---
name: to-spec
description: Turn clarified RuClaw scope into a draft repo spec with explicit acceptance criteria and verification decisions. Does not publish to Jira or approve the spec.
disable-model-invocation: true
---

# To Spec for RuClaw

Synthesize the current conversation, existing docs, and codebase context into a spec. Do not restart the interview unless a blocker makes the spec impossible.

When following `grill-with-docs`, carry forward its resolved decisions and glossary/
ADR changes. For `ask_user_question` answers, use the original question/options and
actual selected/custom answers plus notes. Unanswered, cancelled or failed questions
are unresolved, not implicit acceptance; notes alone do not approve unselected choices.
Later user corrections take precedence. A directly written `согласен` accepts only
that question's explicit recommendation, not all alternatives. Use the questionnaire
for remaining material decisions when available; otherwise ask in ordinary chat and
wait. The form is optional; ordinary conversation is equally valid.

## RuClaw workflow constraints

- Use the RuClaw profile and relevant rows of its area map. Read only applicable
  code/contracts; do not bulk-load repository agent/workflow files.
- The spec is a repo file: `docs/specs/RCL-XXX-<slug>-spec.md`.
- Jira gets only a short mirror comment with a link later; do not create Jira issues and do not paste the full spec into Jira.
- Keep one RCL ticket = one branch = one MR.
- Use the relevant `CONTEXT.md` definitions as the shared project language and
  carry forward the interview's agreed glossary delta. Do not introduce a second
  vocabulary in the spec. If a needed term is missing or conflicts with code/user
  intent, resolve its meaning and propose a focused glossary update; do not treat
  glossary/spec/ADR text as proof of runtime behavior.
- For new/refactored business rules, describe the core responsibility and actual
  runtime connection; do not assume a draft domain model already enforces them.

## Process

1. Identify the RCL ticket from the branch name, user request, or conversation. If missing, ask for it.
2. Explore relevant code/docs if needed.
3. Define observable acceptance criteria and risk-based test seams. Consult the
   profile's `testing.md` for current entry points; do not require one highest
   seam when focused unit/contract tests better prove the invariant.
4. Ask only about unresolved product decisions or material trade-offs. Record
   non-blocking assumptions/open questions as such, not as approved requirements.
5. Write `docs/specs/RCL-XXX-<slug>-spec.md`; do not approve it on the user's behalf.

## Required spec header

Start the file with:

```markdown
# RCL-XXX: <Title>

**Status:** draft
**Ticket:** RCL-XXX
**Target branch:** <intended feature branch, or not created yet>
**Date:** YYYY-MM-DD
```

## Spec template

```markdown
## Problem Statement

The user-visible problem.

## Solution

The proposed user-visible solution.

## User Stories

1. As an <actor>, I want <feature>, so that <benefit>.

## Acceptance Criteria

- [ ] Observable behavior and a verifiable result, including relevant negative paths.
- [ ] Compatibility/security constraints that must remain true.

## Implementation Decisions

- Key modules/interfaces/contracts that will change.
- Architectural or schema decisions.
- Technical clarifications.

Avoid detailed file paths and code snippets unless a prototype snippet is the clearest expression of a decision.

## Testing Decisions

- Map acceptance criteria and risky invariants to focused unit/contract/integration/e2e checks.
- Existing seams/prior art, required test scopes and external prerequisites.
- Verification gaps; do not present proposed future test commands as implemented.

## Out of Scope

- Explicit non-goals.

## Rollout / Migration Notes

- Backward compatibility, data migration, config, deployment, or operational notes if relevant.

## Further Notes

- Remaining context that matters but does not fit above.
```

## Completion

After writing the file, report:

- spec path;
- any assumptions;
- whether a Jira mirror comment is pending;
- suggested next command: `/skill:to-tickets <spec-path>`.
