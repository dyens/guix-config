---
name: grill-with-docs
description: Relentlessly interview the user about an engineering idea or plan, while capturing RuClaw domain terms and hard-to-reverse decisions in repo docs. Use before to-spec when the plan is unclear or architectural.
disable-model-invocation: true
---

# Grill with Docs for RuClaw

Interview the user until you reach shared understanding. Do not implement code during this skill.

This is a Pi/RuClaw adaptation of Matt Pocock's grilling + domain-modeling flow.

## RuClaw workflow constraints

- Respect `docs/agents/workflow.md`: one RCL ticket = one branch = one MR.
- `grill-with-docs` does not create branches.
- ADRs are committed later on the current feature branch by the user/implementer.
- Use RuClaw's canonical domain glossary file: `CONTEXT.md` at repo root.
- Record hard-to-reverse decisions under `docs/adr/` using the next sequential ADR number.
- Do not create Jira issues. Jira may receive a short mirror comment later, but repo docs are the source of truth.

## Interview loop

Map the topic as a design tree: decisions branch into dependent decisions.

Work in rounds:

1. Identify the current frontier: questions whose prerequisites are already settled.
2. Ask the whole frontier in one round.
3. Number questions and give your recommended answer for each.
4. Wait for the user's answers.
5. Recompute the frontier.

Format each question like:

```markdown
❓ **Q1 - <question title>**

<question body, options, trade-offs>

➡️ **Recommended answer:** <your recommendation and why>
```

A question whose answer depends on another unsettled question belongs to a later round.

Finding facts is the agent's job. If a question can be answered by reading the repo, inspect the repo instead of asking the user. Ask only for decisions, priorities, and intent.

The session ends when the frontier is empty. Do not proceed to spec until the user confirms shared understanding.

## Domain modeling during the interview

Actively sharpen language:

- If the user uses a fuzzy term, propose a precise canonical term.
- If the user uses a term conflicting with `CONTEXT.md`, call it out and ask which meaning is intended.
- If the code contradicts the stated model, surface the contradiction.
- Use concrete edge-case scenarios to test boundaries.

Update `CONTEXT.md` inline when a term is resolved and genuinely useful across sessions. Keep it glossary-like: no implementation plan, no scratch notes.

## ADR policy

Offer an ADR only when all are true:

1. The decision is hard to reverse.
2. A future reader would find it surprising without context.
3. Real alternatives were considered and rejected.

If an ADR is warranted:

- Create `docs/adr/NNNN-short-title.md`, using the next number after existing ADRs.
- Include: Status, Context, Decision, Consequences, Alternatives considered.
- Keep it concise and decision-focused.

## Output before handing off to `to-spec`

End with:

- settled decisions;
- glossary changes made or proposed;
- ADRs created or proposed;
- open questions, if any;
- confidence: `ready for to-spec` / `needs more grilling` / `prototype first`.
