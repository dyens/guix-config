---
name: to-tickets
description: Break a plan, spec, or the current conversation into tracer-bullet tickets with blocking edges, written as local files so one feature stays one tracker ticket, one branch and one MR.
disable-model-invocation: true
---

# To Tickets (local slices)

Follow `mattpocock-skills:to-tickets` for everything about **what** a ticket is — vertical
tracer-bullet slices, blocking edges, the expand–contract exception for wide refactors, and
quizzing the user on the breakdown before publishing.

This skill overrides one thing: **where the tickets go.**

## Do not publish slices to the issue tracker

The feature already has exactly one ticket on the tracker — the spec that `/to-spec`
published. That ticket is the feature: one branch, one merge request, one review, one round
of pulling colleagues in. Its slices are working material, not tracker entries.

So publish the approved breakdown as **local files**, exactly as the local-tracker form of
`mattpocock-skills:to-tickets` describes:

- One file per slice at `.scratch/<parent-ticket>/issues/<NN>-<slug>.md`, numbered from `01`
  in dependency order, blockers first. Never a single combined file.
- Use that skill's local-ticket template: what to build, `Blocked by:` naming the other
  slices by number, a `Status:` line, and the acceptance criteria.
- Do not create tracker issues for slices, and do not modify the parent ticket.
- If `.scratch/` is not git-ignored in this repo, say so and ask before writing — the slices
  are scaffolding, not repo history.

## When a slice deserves its own tracker ticket

Only when it genuinely needs separate tracking: somebody else will pick it up, it slips out
of this release, or it turns out to be unrelated work. Then it becomes an ordinary ticket
with its own branch and its own MR. Raise it with the user rather than deciding alone.

## Hand-off

End by telling the user the branch to create for the parent ticket, and that each slice is
built with `/implement` in its own session, context cleared between slices, review once at
the end.
