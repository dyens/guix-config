---
name: grill-with-docs
description: Interview the user about an engineering idea or plan, resolving decisions while capturing RuClaw domain terms and hard-to-reverse decisions in repo docs. Use before to-spec when the plan is unclear or architectural.
disable-model-invocation: true
---

# Grill with Docs for RuClaw

Interview the user until you reach shared understanding. Do not implement code or
create branches during this skill. This adapts the grilling + domain-modeling flow.

## Workflow constraints

- Use the RuClaw profile and its selective area map as orientation, not proof of
  current behavior. Compare relevant documents with code/wiring; distinguish
  observed behavior, intended architecture and unresolved contradictions.
- `CONTEXT.md` is the maintained shared language of the project, not incidental
  background. At the start inspect its relevant sections, including `_Avoid_`
  aliases, and use agreed terms consistently in questions and decisions.
  Check code/domain usage too; a draft implementation is not automatically a
  better definition. Surface contradictions rather than silently choosing a side.
- Do not create Jira issues, branches or commits during the interview. Updating
  agreed glossary terms is part of its documentation work; ADR creation still
  needs explicit approval. Respect any discussion-only/read-only restriction.
- Read relevant code/docs to establish facts instead of asking the user to find
  them. Ask for decisions, priorities and intent, not facts available in the repo.

## Interview loop

Map the topic as a design tree. In each round ask a small, coherent set of
questions whose prerequisites are settled; prioritize decisions that unblock the
next step. Do not dump the whole tree on the user. Dependent questions belong to
later rounds. Give each question an ID, concrete options/trade-offs and one recommended
answer with its rationale. Make the recommendation explicit so “согласен” has a
clear meaning. Do not bundle multiple independent decisions into one question.

When `ask_user_question` is available, use it for each decision round: 1-4 independent
questions, each with a short header, full question/ID and 2-4 concrete options. Put
trade-offs in descriptions and mark the recommended option with its reason. The tool
adds a custom-answer row; do not author reserved Other/Type something./Next options.
Use multiSelect only for genuinely combinable choices, not mutually exclusive designs.
Keep the next round dependent on actual answers, not speculative branches.

If the tool is unavailable (including headless runs), ask the same bounded questions
as ordinary chat text and wait for a reply; do not install tools or guess answers.
Ordinary conversation remains equally valid. Respect custom text, per-question/global
notes and later corrections. Partial submission leaves unanswered decisions OPEN;
cancellation, UI failure or a note alone is not approval of any unselected option.
Never treat a recommendation/default as user consent. A directly written `согласен`
accepts only the clearly stated recommendation for that question.

The questionnaire is an input UI, not authority to edit docs or implement code. Record
settled decisions with their question/answer provenance; plan-cycle retains completed
questionnaire call/result pairs across steps, not just a builder summary. Wait for
actual user answers; recompute the frontier rather than automatically proceeding to
spec or implementation.

## Domain modeling

- Compare each new/changed domain concept with `CONTEXT.md`: reuse an existing
  term or explicitly resolve a distinction, synonym or misleading old definition.
- Discuss a concise definition, boundaries and a concrete example/counterexample;
  use tenant/private-data edge cases where relevant. Do not create a glossary
  entry for every implementation detail or temporary task label.
- After the user agrees a definition, update the corresponding `CONTEXT.md` entry
  in its existing style (term, meaning, `_Avoid_` when useful). Keep one definition,
  not a duplicate glossary in scratch/spec. Update only agreed terms; do not rename
  unrelated concepts or rewrite the entire file. If no term changed, say so.
- If editing is prohibited or a definition is unsettled, keep a proposed glossary
  delta and the open decision in the discussion/working plan. Do not present it
  as adopted language. Missing `CONTEXT.md` is a gap to resolve, not permission to
  invent another canonical file.
- The glossary describes intended language, not proof of runtime enforcement.
  Flag code migration gaps without silently changing agreed meaning to fit legacy.
  Approval of terminology does not authorize implementation, branch creation or
  commits. Keep architecture plans and execution notes outside the glossary.

## ADR policy

Offer an ADR only for a hard-to-reverse decision, surprising without its context,
where real alternatives were considered and rejected. Use the next sequential
`docs/adr/NNNN-short-title.md`; include Status, Context, Decision, Consequences and
Alternatives considered. Keep it concise. Commit later on the feature branch.

## Completion

When the frontier is empty, summarize settled decisions, `CONTEXT.md` changes
(or no glossary delta), approved ADRs, remaining questions and readiness (`ready for to-spec`, `needs more discussion`,
`prototype first`). Confirm shared understanding, then suggest
`/skill:to-spec`; do not restart the interview there. The complete workflow is:

`grill-with-docs → to-spec → to-tickets → implement → code-review`.

Spec and ticket generation remain separate user-invoked steps. Implementation
owns independent code review, checks and publication under its own contract.
