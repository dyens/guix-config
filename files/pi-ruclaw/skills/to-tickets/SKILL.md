---
name: to-tickets
description: Break a RuClaw spec or plan into local tracer-bullet sub-ticket files under .scratch/<RCL>/issues. Never creates Jira issues.
disable-model-invocation: true
---

# To Tickets for RuClaw

Break a spec, plan, or current conversation into local sub-tickets for implementation.

## RuClaw workflow constraints

- Respect `docs/agents/workflow.md`.
- Do not create Jira issues.
- Do not create branches.
- Sub-tickets are local files under `.scratch/<TICKET>/issues/`.
- Also maintain `.scratch/<TICKET>/README.md` with dependency graph, current frontier, and human-only items.
- `.scratch/` is local and not the durable team source of truth.

## Process

1. Read the supplied spec path, ticket, or conversation context.
2. Explore the codebase enough to understand vertical slices and dependencies.
3. Draft tracer-bullet sub-tickets.
4. Present the proposed breakdown before writing files.
5. Ask the user to approve granularity and blocking edges.
6. After approval, write one file per sub-ticket.

## Slice rules

- Prefer vertical tracer bullets: narrow but complete paths through schema/API/backend/UI/tests where applicable.
- Each completed ticket should be independently verifiable.
- Each ticket should fit in one fresh context window.
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

<short context and links to spec/ADR if useful>

## Acceptance criteria

- [ ] <criterion 1>
- [ ] <criterion 2>

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
