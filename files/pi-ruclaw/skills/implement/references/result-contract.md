# Agent results: short answer and independently readable details

The producer writes the result in its assigned artifact directory. Do not generate
one monolithic report for the parent to split, extract, truncate or bulk-read.
The parent creates and assigns an absolute writable directory inside the task's
`.scratch` area BEFORE launch. Each role/pass/candidate gets its own directory.
Do not overwrite a previous candidate's result or another agent's artifacts.

Typical review result:

```text
review/<pass-id>/
  short.md
  findings/F01.md
  findings/F02.md
  coverage.md
  checks.md
```

Ops additionally writes `resources.md`; large commands/logs are separate referenced
files. Group small related details when useful, but each issue must be independently
addressable. There is no line/character quota on answers and no extraction helper.
Keep the short answer an index, not a second copy of the full answer.

## Producer contract

Read the relevant pi-subagents guidance; confirm the resolved custom role policy
at first use. Assign task/spec, exact base/head, evidence mode, invariants, required
coverage/checks, authority, stop conditions and the result directory. An independent
first pass must not receive earlier findings. Reviewer source/test restrictions
and ops resource limits still apply; write permission is ONLY for assigned artifacts.

Write details first and `short.md` last. Until the child is terminal and the index
is complete, the result is pending. `short.md` contains:
- identity: role/pass, task, original base, reviewed/deployed head, evidence mode;
- verdict/outcome, readiness blockers, unavailable scope and skipped/pending gates;
- COMPLETE issue/gap index: stable namespaced ID, severity, one-sentence issue,
  affected location, detail-file link. Explicit zero counts when applicable;
- links to coverage/checks and, for ops, resources/cleanup state.

No hidden overflow: a long index is preferable to undisclosed blockers. Do not put
full reasoning, patches, long command output or logs in the short answer.

Each finding detail states severity/axis, snapshot, affected path/symbol, reachable
scenario, evidence, violated invariant, bounded impact, counterarguments and a
minimal fix direction. Coverage accounts for all assigned paths/batches, integration,
independent passes, exclusions and carried evidence. Checks include command, cwd,
source/deployed identity, exit/result or not-run reason, environment/input equivalence
and log links. Ops resources include ownership, live IDs, deployed source, allowed
operations, cleanup outcome and safe continuation instructions. Never include secrets.

## Native runtime mode for multi-file results

For EVERY reviewer/ops child use `output: false` and `outputMode: "inline"`.
These are child parameters in `runs.run` / each `runs.all` item (or a supported
direct launch), not invented fields on an outer workflow. Roles default to this
mode, but check that launch overrides have not replaced it.

```js
const child = await runs.run('review', {
  agent: 'ruclaw-plan-reviewer', label: 'Review completed task candidate', context: 'fresh',
  output: false, outputMode: 'inline',
  task: '<full bounded assignment, exact SHAs, authority and absolute result directory>',
});
return { ok: child.ok, runId: child.runId, error: child.error ?? null };
```

`inline` applies ONLY to the final completion message: return status and artifact
paths there, never full findings/logs. Detailed results are written directly with
`write` inside the assigned directory; do not dump child output/results/transcripts
into the parent workflow return. Preserve failures and partial-result paths.

Do NOT combine this contract with `output: '<receipt.md>'` / `outputMode: "file-only"`.
The installed runtime injects an AUTHORITATIVE SINGLE-PATH instruction into both
system/task prompts and says to ignore all other destinations, even for a receipt.
It is not merely a transport binding. `output: false` disables that override;
`outputMode: "inline"` avoids the file-only-without-path validation failure.
Never tell a child to disobey a runtime override. If one is unexpectedly present,
report the setup conflict; fix the next launch parameters, not product code.

## Consumer contract

1. Read `short.md` and the parent's current plan/result index. Enumerate ALL findings,
   gaps and required gates before selecting work; do not cherry-pick easy issues.
2. Choose one issue or related group. Read its detail file, needed coverage/check
   evidence and relevant exact-snapshot source. Reading a short answer alone is
   never enough to confirm, reject or close a finding.
3. Record the decision separately in the short plan or a linked decision/result
   file. Never mutate the producer's historical result to make it appear clean.
   Duplicate issues may share one decision, retaining both IDs.
4. A fix is `fixed-awaiting-verification`, not `closed`. Close only with appropriate
   check/review evidence at the candidate or justified equivalent inputs. Preserve
   disputed/rejected findings with reasons, not silent deletion.
5. At final acceptance reconcile EVERY indexed issue/gap, full coverage, independent
   review and all required verification/publication/resource gates. Reopen evidence
   invalidated by changed inputs. No verdict from short answers or tool success alone.
   A context transition alone does not invalidate a verified decision: use its
   persisted disposition/provenance from the plan/results, not a ritual reread of every
   closed issue. Reopen details when evidence/inputs/reasoning are uncertain.

New findings from follow-ups get a new result directory and explicit lineage;
carry old open IDs/decisions forward. A fresh candidate does not erase prior blockers.
Existing single-output/legacy reports remain historical evidence: do not delete
them or rerun source review merely to change formatting. A runtime/format mismatch
alone does not invalidate an otherwise complete independent review. The parent may
create a navigation-only short index clearly labeled parent-authored, linking the
original producer report/run/SHA/sections. Do not claim the parent index was written
by the reviewer or invent missing coverage/check evidence. Close the format-only
blocker once the report's identity, findings, coverage and verification limits are
accounted for; substantive missing evidence remains an open gate. When needed, create a current short index with
exact snapshot/issue IDs and links to existing evidence; migrate details only for
the selected issue, never bulk-reload history for protocol compliance.
In the default plan-cycle v2 process, group related findings into sequential plan
steps. Final review findings become a new short fix plan; no reset per tiny test.
`plan-cycle.md` defines current safeguards. Legacy work-cycles/resume references
apply only to explicit legacy recovery, not new tasks. Read only current-step
result indexes/details, not all historical short answers on every restoration.
