---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Read the repo's `AGENTS.md` / `CLAUDE.md` first — build tags, package manager, commit
message format and test commands are repo-specific and are not repeated here.

Use `mattpocock-skills:tdd` where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the
end.

## One branch per feature

**Do not create a branch.** Every ticket belonging to one feature lands on the branch that is
already checked out, one commit per ticket, so the whole feature is reviewed in a single pull
/ merge request at the end.

If the checked-out branch does not belong to this feature, stop and ask — never switch or
create one unasked.

## Review is per branch, not per ticket

**Do not review after each ticket.** Instead, when the ticket is done:

1. Commit it, following the repo's commit message format.
2. Mark the ticket done wherever it lives.
3. Check whether unfinished tickets remain for this feature.

**If tickets remain** — report what landed and what is left, then stop, so the user can clear
context and take the next one. No review.

**If this was the last ticket** — the feature is complete, so review the whole branch now, in
two passes against the branch point (three-dot diff, e.g. `git diff develop...HEAD`):

- `/mattpocock-skills:code-review` — Standards + Spec. The prefix is mandatory: a bare
  `/code-review` resolves to Claude Code's built-in skill instead. Two things it needs handed
  to it, because it will not find them on its own:
  - **The standards source.** It looks for `CODING_STANDARDS.md` or `CONTRIBUTING.md` and
    nothing else, so in a repo whose rules live in `AGENTS.md` / `CLAUDE.md`, ADRs, or a
    contributing guide under `docs/`, name those files explicitly — otherwise the Standards
    axis falls back to generic code smells and reviews nothing repo-specific. Also tell it
    which rules the repo's CI already enforces, so it does not spend the review there.
  - **The spec.** It scans commit messages for `#123`/`!67`-style references and will miss a
    `PROJ-123` one, so pass the originating ticket explicitly.
- `/code-review high` — the built-in correctness pass.

Report the two passes side by side without merging their findings, fix what is in scope on
this branch, and only then is the branch ready for its MR.
