# RuClaw — selective context map

Read the relevant rows, then follow the code and its dependencies. Repository
paths below are relative to the RuClaw checkout. This file and the test map are
external profile files; use the launcher's absolute Area map / Test map paths with
read, not checkout-relative paths or literal shell variables. This is a navigation map, not a requirement to read every linked document.
Check applicability: neither a document's location nor a core type proves that
its contract is connected to runtime. Resolve material contradictions explicitly.

| Area | Code and useful sources |
|---|---|
| Backend/runtime | `main.go` → `cmd/root.go` → `cmd/gateway.go`. Channel path: `cmd/gateway_consumer*.go` → scheduler → router/loop. User Front chat: `internal/gateway/methods/user_chat.go` → loop directly. Execution: `internal/agent/loop*.go`, `internal/tools/registry.go`, `exposure_resolver.go`; inspect the affected tool/provider and tests. |
| Core migration | `internal/core/domain`, `internal/core/application`, `internal/infra`, `internal/app`. Inspect constructors and callers, not just module descriptions. `core/application/execution` still contains draft/panic scenarios; do not switch live calls to them blindly. Dependency guard: `scripts/ci/check-core-deps.sh`. |
| Tenancy/RBAC/PG | `internal/tenantctx`, `internal/app/rbac.go`, core RBAC/tenancy and their infra adapters. PG seams: `internal/store/pg/{querier,tenant,rlsconn,factory}.go`; provisioning: `scripts/db/provision-roles.sql`. Ordinary stores use `q(ctx)` and explicit transaction helpers; maintenance access is a distinct cross-tenant capability. Tenant context/liveness does not authorize a user. |
| MCP/credbroker | `internal/store/pg/mcp_servers_access.go` selects agent access; `internal/mcp/manager_managed.go` builds runtime tools and credential paths. Management: `internal/http/mcp.go`; User API equipment: `internal/userapi/equipment_transport.go`. Broker: `cmd/credbroker`, `internal/credbroker/{server,mcpbroker,store}`. `cmd/credbroker/README.md` is a selective operational reference. Regenerate `store/sqlcgen` from `queries.sql` with `make credbroker-sqlc`; do not hand-edit generated queries. |
| Settings/bootstrap | `internal/config/{bootstrap,config_load,dead_env}.go`, core domain/application settings, `internal/app/settings.go`, `internal/infra/pg/settings`. `docs/bootstrap-env.md` and `docs/settings-registry.md` are lookup aids; check declarations/consumers. `make settings-doc` updates generated registry sections. |
| Files/knowledge/sandbox | `internal/{filescope,knowledge,objectstore,sandbox}`, `internal/store/pg`, tools and User API file handlers. Trace ownership/viewer and tenant checks for the touched resource. `cmd/sandboxshim` is a separate process; an available tool is not necessarily sandbox execution. Real data-access coverage must be checked, not inferred from an empty IAM UUID. |
| User API/front | `ui/user-front/src/app/router.tsx`, `src/realtime/user-chat-adapter.ts`; REST contracts in `internal/userapi/contract`, runtime in `internal/userapi`, WS chat in `internal/gateway/methods/user_chat.go`. Go DTOs/endpoint registrations feed `make user-api-generate`; inspect that recipe before changing generated API files. |
| Admin front | `ui/web/src/routes.tsx`, nearby features and API clients. Admin shell also contains public guest/call/credential-link routes; UI guards do not replace backend authorization. It has HeroUI/Tailwind/Zustand; do not assume the same stack in User Front. Both UIs use pnpm and local `package.json` scripts. Shared assets/generation: `ui/design-system`. |
| Sidecars/Python | `services/{stt,tts,docservice,sidecarworker}` each has its own uv project/lock. Go clients: `internal/{stt,tts,docservice,sidecartask}`. Speech uses queue workers; DocService supports HTTP and Rabbit. Inspect the service's own manifest, entry point and Dockerfile; `services/README.md` has useful packaging rationale but an outdated service inventory. Node browser service: `playwright-service`. |
| Dev/build/migrations | Read current Makefile recipes and `scripts/dev/local-compose-up.sh`, `scripts/dev-fronts.sh`. `make up` selects Compose profiles; default dev prepares dependencies for host gateway, other profiles may include gateway/fronts. `dev-fronts` starts backend + UIs, `dev-fronts-only` only UIs, `dev-seed` provisions dev state. Go needs `goolm` (include it in explicit `-tags`). Migrations: `cmd/{migrate,upgrade}.go`, `internal/upgrade`, `migrations/`; do not edit historical migrations or force/reset persistent data. |
| Tests/checks | Read `$PI_RUCLAW_ROOT/profile/testing.md` using the launcher's absolute Test map path when selecting checks. It isolates the current test topology and the replacement checklist; do not assume `make test` is unit-only or use a future scope selector before it exists. |
| Git/changelog | Bundled `git-workflow` skill; `docs_flow/pravila-raboty-s-git.md` for Git conventions, `docs_flow/changelog.md` for release-note trailers/exclusions. Executable checks: `scripts/ci/check-commit-message.sh`, `check-changelog.sh`. Read these before corresponding operations, not as config/security guidance. |

Specs, ADRs, old plans and reports are searchable evidence, not startup reading.
Use the user-selected task to determine scope; inspect linked requirements and
current implementations where needed. Do not enumerate every archive to prove
completeness or silently import rules from stale workflows. Test topology and
other detailed commands belong in the selective references, not `project.md`.
