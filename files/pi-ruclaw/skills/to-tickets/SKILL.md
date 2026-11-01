---
name: to-tickets
description: Break a RuClaw spec or plan into local tracer-bullet sub-ticket files under .scratch/<RCL>/issues. Never creates Jira issues.
disable-model-invocation: true
---

# To Tickets for RuClaw

Break a spec, plan, or current conversation into local sub-tickets for implementation.

## RuClaw workflow constraints

- Use the RuClaw profile and relevant code/contracts, not repository workflow
  bulk-reading. Resolve material scope contradictions before decomposing work.
- Do not create Jira issues.
- Do not create branches.
- Sub-tickets are local files under `.scratch/<TICKET>/issues/`.
- Also maintain `.scratch/<TICKET>/README.md` with dependency graph, current frontier, and human-only items.
- `.scratch/` is local and not the durable team source of truth.

## Process

1. Read the supplied spec and acceptance criteria, or identify the agreed scope
   in the ticket/conversation. Do not silently turn unresolved assumptions into tasks.
2. Explore the codebase enough to understand vertical slices and dependencies.
3. Draft tracer-bullet sub-tickets.
4. Present the proposed breakdown before writing files.
5. Ask the user to approve granularity and blocking edges.
6. After approval, write one file per sub-ticket.

## Slice rules

- Prefer vertical tracer bullets: narrow but complete paths through schema/API/backend/UI/tests where applicable.
- Each completed ticket should be independently verifiable.
- Keep each ticket bounded enough for a fresh execution context; include source
  links and required invariants rather than copying the full spec into every file.
- Assign every source acceptance criterion to a ticket; identify shared checks
  and prerequisites. Do not drop cross-component validation between slices.
- Prefactoring can be its own first ticket if it makes the change easier.
- For wide refactors, use expand → migrate batches → contract.

## Local ticket path

Use:

```text
.scratch/<TICKET>/issues/<NN>-<slug>.md
```

Number tickets in dependency order, blockers first.

## Local ticket template

```markdown
# <NN>: <Ticket title>

**What to build:** <end-to-end behaviour from the user's perspective>

**Blocked by:** <numbers/titles, or "None (can start immediately)">

**Status:** ready-for-agent

## Context

<source spec/task path and relevant criteria/decisions; links to applicable contracts>

## Acceptance criteria

- [ ] <criterion 1>
- [ ] <criterion 2>

## Verification

<checks/test scopes for these criteria, prerequisites, and any shared final gate;
consult the profile's testing.md and current scripts, not future command syntax>

## Implementation notes

<optional; avoid brittle file lists unless genuinely useful>
```

## README template

Write/update `.scratch/<TICKET>/README.md`:

```markdown
# <TICKET> local implementation plan

## Source

- Spec: <path>

## Dependency graph

- 01 ...: blocked by none
- 02 ...: blocked by 01

## Current frontier

- <tickets with no unfinished blockers>

## Human-only / needs decision

- <items or "None">
```

## Completion

Report:

- files written;
- current unblocked frontier;
- recommended next command for the first sub-ticket: `/skill:implement .scratch/<TICKET>/issues/<NN>-<slug>.md`.
