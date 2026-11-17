# Compact child results

Ordinary implementation steps use task_complete(result, checks, handoff), NOT report
files. This contract is only for reviewer/ops children or substantial external evidence.
Do not produce files merely to demonstrate compliance with a workflow.

## One result by default

Parent assigns a unique absolute task-local result directory per pass/candidate.
Child writes `result.md`: a concise, independently understandable result containing:
- role/pass, task, exact original base and examined/deployed head;
- outcome, coverage/exclusions and actual checks (or not-run reason);
- ALL findings/gaps, with stable IDs, severity, location, reachable scenario,
  evidence/invariant and bounded impact/fix direction;
- for ops: owned live resources and cleanup/safe continuation state.

A clean review may be a few paragraphs. Zero findings must still state coverage and
execution limits; source review does not prove tests or live acceptance. Never hide
findings to meet a length target. Split only genuinely large findings/logs into
linked files; no obligatory coverage.md/checks.md/short.md bundle. Do not duplicate
reasoning in an index and details. Keep secrets out of outputs.

Historical multi-file reports remain valid: use existing short.md indexes and read
only relevant detail, not bulk history. No rerun or migration merely for formatting.

## Launch and transport

Reviewer remains fresh, static/report-only with no project/global/skills inheritance;
ops stays within explicit resource/operation authority. Confirm resolved role policy
at first use or when changed. Pass complete task/criteria, exact refs, allowed inputs,
required scope/checks, authority and the writable directory. An independent first
review must not receive builder/peer verdicts as an oracle.

Use output:false and outputMode:inline, never a single-path runtime override:

```js
const child = await runs.run('review', {
  agent: 'ruclaw-plan-reviewer', label: 'Review completed task candidate', context: 'fresh',
  output: false, outputMode: 'inline',
  task: '<bounded task, full criteria, exact base/head, authority and absolute result directory>',
});
return { ok: child.ok, runId: child.runId, error: child.error ?? null };
```

These are child parameters, not fields on an outer workflow. Direct single-child
launch/resume is sufficient; scripted orchestration is not mandatory. Load tool
references only for unknown operations, errors or API changes, not every boundary.

Final inline completion contains concise outcome, blockers and result path, not a
copy of the report. Parent reads result.md only after child terminal completion.
Failure/partial output is not a passed gate. If an AUTHORITATIVE SINGLE-PATH runtime
instruction appears, report setup conflict and fix the next launch; never disobey it.

## Findings and follow-up

Read all findings/gaps once; inspect exact-source evidence and relevant detail when
validating a finding. Save concise dispositions and open IDs in task notes/handoff;
long reasoning may use a linked file, not an obligatory second ledger. Historical
child results are immutable. Duplicate IDs can share a reasoned disposition.
A fix awaits appropriate verification/review; it is not closed just because edited.

Follow-ups examine previous reviewed head..new head plus affected invariants, carry
valid coverage honestly and preserve open IDs. New candidate does not erase blockers.
Reopen when relevant inputs invalidate evidence, not merely because context reset.
Final acceptance reconciles all findings, criteria and mandatory checks/resources/
publication gates. Unavailable coverage or skipped checks are explicit gaps.
