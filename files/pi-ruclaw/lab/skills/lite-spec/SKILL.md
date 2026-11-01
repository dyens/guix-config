---
name: lite-spec
description: Agree a small brownfield change using proposal, spec deltas, design decisions and acceptance scenarios; no implementation before user approval.
disable-model-invocation: true
---
# Agree the change

OpenSpec-inspired artifact pattern, not an OpenSpec CLI installation/schema.
Use existing approved specs if sufficient; never migrate/rewrite them for ceremony.

1. Read the request, relevant code/contracts and CONTEXT.md terms. Ask only questions
   that affect behavior, security boundaries, scope or an acceptance decision.
2. Draft one change note: why/what, explicit non-goals, changed requirements with
   WHEN/THEN examples, failure/isolation cases, essential design decisions and
   the cheapest adequate verification for each scenario. Link existing sources.
3. Do not over-specify speculative interfaces/implementation steps or expand scope.
   Separate observed legacy behavior from user-approved intent.
4. Get user approval of material choices. The approved note is the builder/evaluator
   contract; it does not grant commit/push/infrastructure authority automatically.

For a substantial spec, proposal/spec-deltas/design/tasks may be separate files.
For a small change one note suffices. Do not create a second task/status database.
