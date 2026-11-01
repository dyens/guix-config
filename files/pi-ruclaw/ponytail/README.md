# Ponytail full — opt-in experiment

Uses the existing plan-cycle v2, but REPLACES our code-writing/review policies with
[ponytail](https://github.com/DietrichGebert/ponytail/blob/09c434ab73ca43761c5d8b0c5d341926c2fba710/skills/ponytail/SKILL.md)
and [ponytail-review](https://github.com/DietrichGebert/ponytail/blob/09c434ab73ca43761c5d8b0c5d341926c2fba710/skills/ponytail-review/SKILL.md).
Pinned commit: `09c434ab73ca43761c5d8b0c5d341926c2fba710`. Verbatim upstream Markdown
and MIT license are vendored; hashes/URLs in `vendor/provenance.json`. No upstream
scripts or package manager are installed/executed; no new dependencies.

## What changes

- `implement` reads Ponytail **full** before intake/checkpoint 0.
- The old project architecture/design directives, selective-context prescriptions
  and Design/checks paragraph are replaced, not combined with Ponytail.
- `code-review` and both review roles use upstream ponytail-review instead of our
  review/risk checklists. Full upstream report format is preserved in report.md;
  short.md is only the artifact index. Reviewers remain fresh and report-only.
- User task/spec/contracts, security, authority, original Git base/ownership,
  sequential plan boundaries, test-result honesty and cleanup stay in force.
- Test entry-point facts stay available; expensive task-required tests are NOT
  waived by Ponytail's minimal-test guideline. Shortcut comments never waive task
  criteria, security or real permissions. Ship is not publication authority.

Default profile, ordinary Pi, Lite, installed aliases and existing sessions do NOT
change. Do not switch an active/default/legacy session silently to this variant.

## Prepare a frozen runtime

```sh
python3 files/pi-ruclaw/ponytail/prepare.py /tmp/ruclaw-ponytail-runtime
python3 /tmp/ruclaw-ponytail-runtime/pi-ruclaw/launch.py --check
```

Destination must not exist. This copies the current profile/runtime into it, applies
small explicit overrides, verifies vendored hashes and records all output hashes in
`pi-ruclaw/ponytail-runtime.json`. It does not edit the source or product checkout.
`--source /path/to/frozen/pi-ruclaw` permits comparison against an earlier exact
profile; this experiment uses the prior v2 task01 frozen runtime as its control.
The copied launch.py retains its usual configured-checkout/direnv behavior. For a
worktree experiment, use its make_plan(worktree, root=frozen_profile, environ=env)
as in the existing pilots; do not launch the stock CLI expecting a worktree switch.

## Validation (no model calls)

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s files/pi-ruclaw/tests -p 'test_*.py'
node files/pi-ruclaw/tests/runtime-smoke.mjs
PI_RUCLAW_TEST_PROFILE_ROOT=/tmp/ruclaw-ponytail-runtime/pi-ruclaw \
  node files/pi-ruclaw/tests/runtime-smoke.mjs
```

These check actual skill/role loading, native plan-cycle/child-policy wiring and
policy separation, NOT code quality. Quality/cost comparison needs a new task run
from the same original input/base/model and the already-frozen common behavioral
checks afterward. Keep prior solutions, audits and counterexamples out of the
builder's/reviewer's context. One run is not a general process benchmark.
