# RuClaw — current test map

Selective reference, not startup context. Audited statically at `ac612deef`;
commands below were inspected, not run as part of the audit. Test organization
is due to change: recheck current recipes, package scripts, gates and CI rules
before execution. Keep command/topology changes here, not in `project.md`.
Paths and commands below are relative to the RuClaw checkout.

## Current entry points

| Scope | Entry point and important boundary |
|---|---|
| Focused Go/unit | `make test-unit` runs `go test ./...`; prefer the affected package and regression first. Integration-gated tests may skip, so this does not prove PG/S3/broker coverage. Include `goolm` in explicit build tags; direct Go calls need the same tag setup as Makefile. |
| Full Go/wiring | `make test` delegates to `test-wiring`, not unit-only. Its wrapper starts PG/S3/Rabbit containers, provisions roles and migrations, then runs `_test-wiring-run`. That recipe runs vet, serial uncached integration packages and a disjoint unit group, then merges coverage. Inspect it before use. |
| Broker-focused wiring | `make test-wiring-broker` selects a dedicated package set with integration opt-in and `-p 1`, backed by its own wrapper/provisioning targets. Read the current package set and required endpoints rather than copying the full wiring environment. |
| Prepared-stand E2E | `make e2e` runs `./tests/e2e/...` with `-p 1`, `-count=1`, explicit timeout/concurrency. `make e2e-report E2E_GROUPS=...` selects package groups and writes `e2e-report/tier.{json,log}`. This is not stand provisioning. |
| Selected E2E smoke | `make e2e-smoke E2E_SUITES=chat,cron` selects named suites through `scripts/ci/run-e2e-smoke.sh`, not `E2E_GROUPS`. Validate accepted names there. Reports: `e2e-report/smoke.{json,log}`. A smoke subset is not the full E2E tier. |
| Admin UI | In `ui/web`: `pnpm test`, `pnpm typecheck`, `pnpm lint`, `pnpm build`. `test:e2e:integration` needs its configured live gateway/auth; `test:static` is a separate script. Root frontend test targets cover Admin, not automatically User Front. |
| User Front | In `ui/user-front`: `pnpm test`, `pnpm typecheck`, `pnpm lint`, `pnpm build`; additional production/canonical/budget/theme scripts in its manifest. Inspect each script's fixtures and runtime requirements; canonical/mockup checks are not evidence of live deployment. |
| Python | From the affected service directory: use its uv lock and local pytest/ruff/mypy configuration. `uv sync --frozen` may install/download dependencies; `uv run pytest`, `uv run ruff check .`, `uv run mypy` follow that service's config. DocService lint/typecheck covers selected files, unlike an assumed whole-service strict gate. |
| Browser sidecar | `playwright-service/package.json`: `npm test` runs Node tests; inspect fixtures and browser requirements. It is not one of the pnpm UI projects. |
| Structural/contracts | Follow the touched area: core deps, store querier, tenant door, RLS coverage, migration numbering, generated settings/API/sqlc, commit/changelog. Sources: `scripts/ci/`, nearby tests and `.gitlab-ci.yml`. Job presence does not mean it runs for every diff. |

## Candidate preflight and final verification

Before final review/heavy execution, derive a small **change -> applicable CI gate**
map from the current Makefile, package manifests, `.gitlab-ci.yml` and included jobs
(including their rules/config). This table is a lookup guide, not a new dispatcher
or a claim that every listed job applies. Include changed tests/scripts, not just
runtime code. Record required checks and explicit local-unavailable gaps.

| Changed area | Cheap preflight to resolve from current scripts/CI |
|---|---|
| Go source or tests | gofmt/diff, affected compile/tests/vet and applicable lint/security checks, including gosec when required by CI. Use CI-pinned Go/linter versions, config and build tags; a host-tool pass is not CI parity. |
| UI source/config | Relevant pnpm lint/typecheck/focused tests; lock/generated parity where affected. |
| Python service/tests | Service-local lint/typecheck/focused pytest with its lock/config and CI Python version. |
| CI/Helm/schema/generated | Applicable config/selection/render, migration numbering and canonical generated/archive parity checks; inspect execution safety first. |

Run focused regressions while editing. Once coherent and preflighted, commit with
permission and run independent static review alongside required heavy verification
on the SAME immutable candidate when resources permit. Review does not execute tests
or replace preflight. If a required preflight is unavailable, disclose the gap before
review; review may inspect source but cannot close missing mandatory verification.
No edits to active test inputs; finish/stop runs before fixes or use verified isolated
snapshots. Never run shared-DB suites concurrently merely to overlap review/testing.
All required gates must be reconciled before acceptance/publication, regardless of
completion order. See implement/references/plan-cycle.md for input-equivalence and
the linked check index; no rerun solely for a context reset/new commit.

For NEW integration regressions, run the test alone/first on fresh task-owned backend
resources: it must create its own required bucket/schema/fixtures rather than rely on
another test/package's order. Check repeat/existing-resource behavior where relevant.
Keep role isolation and real production assertions; do not weaken checks to make the
clean run pass. An existing prepared backend alone does not prove fixture autonomy.

## Execution boundaries

- Read wrapper recipes before starting integration checks. Current wiring targets
  use fixed container names and remove/recreate them; confirm ownership and avoid
  concurrent runs before touching those resources. No global cleanup/prune.
- Shared-DB packages run serially. Do not globally export
  `RUCLAW_TEST_INTEGRATION=1` and then run unconstrained `go test ./...`:
  packages may interfere through cleanup. `internal/testinfra` and broker-specific
  gates determine skip/fail behavior; inspect actual skips and backend availability.
- PG security checks need the split app/owner/maintenance role model. A green
  run as superuser is not proof of RLS. Do not inherit an unrelated stand's DSN.
- Stand tests act on real prepared resources. Confirm target, isolation, credentials
  source and test settings before running. Use fake-model scenarios where applicable;
  real-model/shared-environment actions need explicit authority. Do not print env.
- Preserve process exit status, selected scope, source revision and skip/failure
  information. A listed command, successful build or missing dependency is not a
  passed test. Do not weaken assertions or label an omitted scope as covered.
- `docs/testing/stand-contract.md` is a detailed lookup source for the relevant
  stand scenario, not mandatory bulk reading or proof that old topology is current.

## Re-audit when test organization changes

Replace the current-entry table after checking:

1. Dispatcher: actual Makefile/script targets, selector syntax, valid scope names,
   default scope, and behavior for unknown/empty selections.
2. Scope → packages/scenarios: what runs, what skips, prerequisite services,
   role/identity requirements and generated fixtures/contracts.
3. Isolation/lifecycle: who provisions and owns stand/DB/containers; which scopes
   may run concurrently; cleanup and shared-resource constraints.
4. CI parity: selected scopes, job rules, required gates, reports and failure/skip
   propagation. Do not infer CI parity from a local dispatcher name.
5. Update this file and its row in `areas.md`; leave the product description
   unchanged unless a genuine architectural boundary changed.

The proposed future `TEST_TYPE` scope dispatcher is not documented here as an
available command. Verify its implementation before replacing these entry points.
