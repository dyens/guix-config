# Ponytail result transport (not a code-quality checklist)

Parent assigns exact original base/head, task/criteria, authority, relevant evidence
and an absolute unique result directory under task scratch. First independent
review receives no earlier reviewer findings. Preserve historical reports.

Use fresh `ruclaw-plan-reviewer`, `output:false`, `outputMode:"inline"`. No file-only
output override: the native runtime would replace the allowed output destinations.

```js
const child = await runs.run('review', {
  agent: 'ruclaw-plan-reviewer', label: 'Review completed task candidate', context: 'fresh',
  output: false, outputMode: 'inline',
  task: '<original task, exact base/head, authority, evidence and result directory>',
});
return { ok: child.ok, runId: child.runId, error: child.error ?? null };
```

Reviewer writes report.md with the COMPLETE upstream ponytail-review output.
coverage.md lists inspected paths/range and exclusions; checks.md records available
check evidence and what was not executed. Write short.md last: task/base/head,
verdict, a complete index of numbered findings and gaps, links to those files.
The final inline response is status + paths, not a transcript or full report.
Ops writes its check/resource logs in its own directory and indexes them similarly.

Parent reads the full relevant report, validates findings and records dispositions
separately; never rewrites the original review. Every numbered finding and gap must
be addressed or explicitly retained with its reason. Confirmed fixes become another
short sequential plan. A new candidate does not silently close old findings. Missing
execution is not PASS, and Ship is not permission to push or production acceptance.
