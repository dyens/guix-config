---
name: to-spec
description: Turn the current grilled conversation or plan into a RuClaw spec file. Does not publish to Jira; the repo spec is the source of truth.
disable-model-invocation: true
---

# To Spec for RuClaw

Synthesize the current conversation, existing docs, and codebase context into a spec. Do not restart the interview unless a blocker makes the spec impossible.

## RuClaw workflow constraints

- Respect `docs/agents/workflow.md`.
- The spec is a repo file: `docs/specs/RCL-XXX-<slug>-spec.md`.
- Jira gets only a short mirror comment with a link later; do not create Jira issues and do not paste the full spec into Jira.
- Keep one RCL ticket = one branch = one MR.
- Use `CONTEXT.md` vocabulary and respect relevant ADRs.

## Process

1. Identify the RCL ticket from the branch name, user request, or conversation. If missing, ask for it.
2. Explore relevant code/docs if needed.
3. Identify testing seams before writing the spec. Prefer the highest existing seam and the fewest seams possible.
4. If the seam choice is non-obvious, ask the user to confirm it.
5. Write `docs/specs/RCL-XXX-<slug>-spec.md`.

## Required spec header

Start the file with:

```markdown
# RCL-XXX: <Title>

**Status:** draft
**Ticket:** RCL-XXX
**Target branch:** <current branch>
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

## Implementation Decisions

- Key modules/interfaces/contracts that will change.
- Architectural or schema decisions.
- Technical clarifications.

Avoid detailed file paths and code snippets unless a prototype snippet is the clearest expression of a decision.

## Testing Decisions

- Highest seam(s) to test.
- Similar existing tests or prior art.
- What must be covered at unit/integration/e2e level.

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
