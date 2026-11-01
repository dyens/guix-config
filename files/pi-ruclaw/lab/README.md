# Pi RuClaw Lite — acceptance-first profile

Opt-in profile, not an in-place migration of the old pi-ruclaw/runner. No mandatory
context resets, per-finding review loops, implementation workers, new packages or
automatic push/MR. Native Pi compaction/personal context remain unchanged.

## Current process

1. Read approved task and original base; record explicit CURRENT user permissions.
2. **Before implementation**, /lite-acceptance delegates preparation to the existing
   independent evaluator. It derives all criteria, actual producer/consumer seams,
   positive/negative cases and runs permitted baseline checks in owned exports.
3. Parent inspects the criteria/assertions, intended old failures, controls and
   authority. Freeze the agreed suite, retaining its ORIGINAL SHA256 anchor.
4. One continuous builder implements the coherent batch against this contract.
   It does not edit evaluator assertions/tiers to make a failure green.
5. /lite-review runs source review and independent replay of the frozen suite.
   Counterexamples are fixed in a batch, followed by affected-invariant review.
6. Report **requirement acceptance** separately from **delivery readiness**.
   Failed/skipped/blocked required cases prevent the first. Separately agreed
   CI/stand/merged-result gates may block the second, not disappear into "done".

The same evaluator role has PREPARE/VERIFY modes, not a third specialist. There is
one extra preparation invocation before coding; its cost/time must be measured,
not hidden. No claim of quality/speed improvement before a live evaluation.

## Exact operations and frozen contract

- [lite-acceptance](prompts/lite-acceptance.md): exact native prepare recipe, current
  authority handoff, suite JSON schema, baseline evidence, inspection and freeze CLI.
- [lite-review](prompts/lite-review.md): exact candidate recipe with seal and ORIGINAL
  anchor. Missing/mutated suite cannot be replaced silently by candidate-picked tests.
- [acceptance.py](scripts/acceptance.py): validates contract structure, fingerprints
  every suite file and verifies the original seal/anchor/base. Detects added/deleted
  files, changed assertions/authority and symlinks. Never overwrites an existing seal.
  judge rejects missing/duplicate/unknown case results and exact candidate/anchor
  mismatches, and separates requirement acceptance from pending delivery checks.

These hashes protect a previously agreed test set, NOT source-document currency.
They are not a test grader, permission verifier, OS sandbox, proof that assertions
are correct or a hard restriction on an agent that ignores the protocol. Parent
must check all approved IDs and preserve the original anchor outside the builder's
mutable test edits. Scope/authority/test corrections require an explicit decision,
new suite/seal/anchor and retained old evidence. Later user revocations always win.

The writable authority record quotes actual user grants and message provenance;
its existence is not authorization. Explicit fixture bindings/cleanup and role
ceilings accompany fresh evaluators; do not infer permission from parent history.

## Launch a NEW approved task, not a third blind retry

No new product branch/task/model run was started while installing this process.
Choose a fresh authorized linked worktree on experiment/pi-lite-* in the same repo.
Do not continue an already-completed comparison session as if it were a clean run.

```sh
python3 ~/vms/guix-config/files/pi-ruclaw/lab/launch.py \
  --worktree /absolute/path/to/fresh-experiment --check
python3 ~/vms/guix-config/files/pi-ruclaw/lab/launch.py \
  --worktree /absolute/path/to/fresh-experiment \
  --provider openai-codex --model gpt-6.1-sol --thinking medium
```

Use /lite-acceptance with the approved task and actual permissions to prepare only;
or /skill:lite-implement with the approved task to run preparation BEFORE source
changes. If permissions/scope are missing, ask narrowly. No blanket infrastructure
permission is supplied by this README. Local commits also need explicit approval.

Direct Python needs no homerec. After Home activation/new shell pi-ruclaw-lite is
equivalent. Launcher explicitly loads both prompts/two skills/native subagents,
excludes repo team context/old cycle extension/generic API-guide skill, and refuses
the primary checkout, unrelated repo or ordinary branch. direnv supplies primary
credentials but cwd/profile variables are restored AFTER it; .envrc is not copied.
A worktree does not isolate Git objects, Docker/DB/network, caches or credentials.
Inspect/scrub test environment; never reuse inherited stand resources/DSNs.

## Prior experiments — retained, NOT fresh launch targets

- Lite v1: experiment/pi-lite-RCL-821-extern-review at8e879041.
- Lite v2: experiment/pi-lite-v2-RCL-821-extern-review atd5189d42.
- Both started from2cbf2458 with the same20 frozen review inputs. Main feature
  checkout was not switched/reset. Aborted manual repairs were backed up/removed.
- [Quality audit](evaluations/RCL-821-quality.md),
  [v2 outcome](evaluations/RCL-821-lite-v2-outcome.md): v2 improved honesty but still
  failed the same three external behavior problems. Do not treat source review,
  49/49 paths or a cheaper parent bill as equivalent quality.

Prior solutions/reports/evaluations are NOT an oracle for a new builder/evaluator.
A repeat of this known task after tuning is not blind evidence of generalization.
Compare all-agent costs, elapsed/approval/test waits, misses/reopened defects,
skips and identical completion criteria; shared caches/host load limit timing.

## Offline checks

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s files/pi-ruclaw/lab/tests -p 'test_*.py'
node --test files/pi-ruclaw/lab/tests/*.test.mjs
node files/pi-ruclaw/lab/tests/runtime-smoke.mjs
```

Native loaders/validator/fake runs verify wiring and contract integrity, NOT model
compliance, live test quality or task completion. See [plan.md](../plan.md) for limitations.

Design references: [Anthropic harness experiments](https://www.anthropic.com/engineering/harness-design-long-running-apps),
[OpenSpec](https://github.com/Fission-AI/OpenSpec),
[named workflow registry pattern](https://github.com/white-hat/pi-subagents-workflows).
No external registry/OpenSpec package installed; existing native workflowScriptPath used.
