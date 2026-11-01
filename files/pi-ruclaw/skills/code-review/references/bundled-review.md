# Bundled review evidence and coverage

Use for broad, risky, GitLab MR or multi-reviewer work under `../SKILL.md`.
This is the mechanical evidence protocol, not a substitute for its review,
independence, verification and verdict gates. Helper paths resolve from the
code-review skill root, not this reference's directory.

## Freeze the exact snapshot

```bash
scripts/prepare-review-bundle.sh <base> <head> .scratch/reviews/<id>/<head-short>
scripts/prepare-review-lanes.sh .scratch/reviews/<id>/<head-short>
```

Use a fresh directory per new snapshot; reuse an existing immutable bundle for
the same base/head only if evidence hashes still match. Never overwrite evidence
or blindly transfer approval. The bundle includes metadata, diff, stat, commits
and an exact exported head-tree (not a Git worktree). Inspect that snapshot, not
mutable checkout files. Git queries run in the source repo with explicit SHAs,
not inside head-tree. Do not execute head-controlled scripts on the host.

## Exhaustive primary assignment

`prepare-review-lanes.sh` assigns every changed path to one primary topic batch;
supplementary inspection may overlap. Default topics: approval, chat runtime,
A2UI, chat UI, contracts/artifacts, ops/docs, backend, frontend, services. Empty
topics are omitted; ordered rules select the first match.

Defaults are at most 12 files, 800 patch lines or 64 KiB patch bytes per batch.
A single oversized file is flagged and needs a dedicated semantic pass; never
truncate it or skip generated artifacts. Read related source at head-tree when
patch context is insufficient. Cover all batches even after discovering blockers.

Outputs:
- `lanes/<batch>/{files.txt,diff.patch,diff-u80.patch,brief.md}`;
- `coverage.json`: exact snapshot, primary assignment and evidence hashes;
- `results.template.json`: pending primary batches;
- `unassigned.txt`: unknown paths.

Unknown paths block preparation. Inspect and supply task-specific ordered rules
with `--rules <json>`, a list of `{ "lane": "name", "pattern": "regex", "brief":
"risk-focused instructions" }`. Custom rules replace defaults. Do not hide gaps
with an unexplained catch-all. Include deletions, renames, fixtures, docs,
migrations, generated files and build configuration.

Before assigning work:

```bash
scripts/prepare-review-lanes.sh <bundle> --validate
```

Coverage PASS proves assignment integrity, not inspection or sufficient independence.
One reviewer may cover multiple batches; agent count is not a coverage metric.
Include the parent skill's end-to-end integration and independent critical-chain
passes where applicable. For A2UI/chat this includes acceptance → store → closure
→ queue/drain, background publication, amendment → schema/policy → dispatch and
preview → action. Separate file reviews do not prove the whole chain.

## Results and synthesis gate

Copy `results.template.json` to `results.json`. Use exactly the manifest's batch
IDs, for example:

```json
{
  "chat-runtime-01": {
    "status": "reviewed",
    "report": "reports/chat-runtime-01.md"
  },
  "approval-01": {
    "status": "gap",
    "report": "reports/approval-01.md",
    "reason": "Exact evidence unavailable; requires another pass"
  }
}
```

Each batch report states inspected scope, invariants, findings or no findings,
and verification gaps. `reviewed` means coverage is justified, not defect-free.
For descendants read `follow-up.md` beside this reference before carrying prior
inspection forward. Map by paths/scope, not potentially changed batch IDs.

Pending/missing results block completion; `gap` requires a reason and yields
REVIEW INCONCLUSIVE. Before synthesis/publication run:

```bash
scripts/prepare-review-lanes.sh <bundle> --validate --results <bundle>/results.json
```

Mechanical validation cannot prove report truthfulness. Parent checks reports
against exact evidence, independently records integration/second-pass results,
and preserves runtime/artifact/spec/CI gaps. Batch completion does not close those
other gates. Follow the parent skill for the final verdict and publication.
