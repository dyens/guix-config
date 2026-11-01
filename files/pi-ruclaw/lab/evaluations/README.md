# RCL-821 pinned quality probes

Purpose: reproduce three specific source-audit counterexamples on both candidates,
not benchmark overall quality/speed or implement fixes.

- Lite: `8e8790416963fd8185df0aa40b7746badad8474a`.
- Original intermediate candidate: `a9b5de71b3ecbe2c718313501177fc475c0070a1`.
- Identical injected probes, both refs available in the same Git repository.
- Source exports are retained; original worktrees/branches are read-only.

## Reproduce from guix-config

Requires Python3.12+, installed Go supporting the source module, Git, and existing
cached Go modules. No dependency installer, direnv or model invocation is used.
Pick a NEW output directory outside ALL product worktrees:

```sh
python3 files/pi-ruclaw/lab/evaluations/run-quality-probes.py \
  --repo /home/dyens/dev/croc/ruclaw \
  --out /tmp/pi-ruclaw-quality-new-run
```

**Exit1 is expected for these pinned candidates:** Lite has regressions. It is not
by itself proof of a product bug. Check `coverage_ok`, individual test outcomes,
no skips and diagnostics in results.json to distinguish compile/infrastructure
failures. The runner also exits1 on missing probe coverage, skips or failed tests.
It refuses existing output directories and any output inside a product worktree.

The runner exports immutable commits with git archive and adds the test sources
only inside those exports. It uses an empty HOME and an allowlisted environment,
GOWORK off, Go env config off, module fetching off, -mod=readonly and bounded
parallelism/timeouts. The module/build caches are shared, so timings are not A/B
performance measurements. No LFS smudge or media validation.

Network: owned temporary HTTP loopback and TLS private-interface fixtures; the
existing product testinfra resolves this host's hostname and listens on a random
private-interface port, not loopback. Ports close at test cleanup. No Docker,
real databases, inherited stand endpoints, GitLab, model or deployment calls.
This is not an OS/network sandbox: execute only trusted snapshots/probes.

## What the probes do

- `selection_test.go`: actual Loop + common document_ids finalizer + after_tool
  acceptance, mock owned DocumentStore. Allow/deny/no-selection controls. Observes
  final attachment IDs, NOT complete A2A ingress or actual browser/download delivery.
- `envelope_test.go`: actual broker private HTTP writer/client, TLS partner,
  credential-free URL ingestion, actual file bodies at16B/750KiB/1MiB. Direct,
  non-streaming partner fallback and real SSE; checks preserved text/file_error,
  exact bytes, no reusable authority, one send and one download per case.
- `polling_test.go`: actual broker polling against TLS partner. Second physical
  GET is gated; first working snapshot must have reached the iterator before that
  gate. Releases/joins explicitly. Not a UI/browser or arbitrary latency test.

These files depend on test helpers in BOTH source snapshots. They are not a
standalone Go package in guix-config; compile/run via the runner, not `go test`
from this probes directory. Gopls there has no module root. Actual compilation
of all three injected files succeeded in both exports.

## Retained evidence

`results/2026-10-24/`: final runner/probe/archive fingerprints, complete Go JSON
logs, exact invocation and outcomes. Lite9/13 leaf cases pass; original13/13;
zero skips. There are15 records including parent groups. Two runs agreed.
This is targeted evidence of three concrete gaps, not a percentage quality score.
See [audit](RCL-821-quality.md) for all original IDs, caveats and follow-up scope.

No product source fixes or commits were performed by this evaluation.
