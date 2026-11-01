# RuClaw Pi — project profile v2

## Purpose and components

RuClaw is a corporate LLM agent platform: employees use agents centrally through
Web or channels such as Telegram. Agents can act in corporate systems, so access
control and data isolation are central product requirements.

The main Go process assembles the gateway, agent runtime, providers and tools.
PostgreSQL holds application state; object storage holds documents/artifacts.
Sandbox managers provide isolated execution; credbroker is a separate proxy for
credentialed corporate integrations. User Front (`ui/user-front`) and Admin Front
(`ui/web`) are separate React applications. Speech, document and browser work use
specialized sidecars; their transports are not uniformly HTTP.

## Architecture direction

DDD is being introduced incrementally. Put new business rules and refactored
scenarios in `internal/core`, prioritizing human-readable code and explicit rules
rather than elaborate patterns. Domain models express rules; application code
owns scenarios/ports; infrastructure implements adapters; composition connects
these to the running product.

Migration is partial: settings, RBAC and approvals have live core wiring, while
some execution scenarios are drafts. Follow the actual call path before changing
behavior. A domain type alone does not enforce a runtime rule. Connect new rules
to real execution; do not copy legacy bypasses or start an unrelated rewrite.

## Data and trust boundaries

- A tenant usually represents a department, but demo tenants may belong to
  different companies. Isolation must not depend on a shared trusted employer.
- Installation control-plane authority and tenant-data authority are distinct.
  PostgreSQL app/maintenance roles are also distinct from product RBAC roles.
  Keep ordinary tenant work on the scoped path; preserve RLS, tenant filters,
  transaction scope and explicit cross-tenant boundaries.
- Verified IAM identity is not a free-form routing UserID, sender name or session
  key. Preserve identity and authorization through tools and background work.
- Tenant-level MCP access requires an agent grant; agent-level MCP belongs to its
  owner agent. Connection scope and credential mode are separate. Credbroker
  injects shared or personal credentials; personal access requires verified identity.
- If groups are enabled, they must not gain a participant's private data or
  personal credentials. They may have their own shared state. Anonymous is not
  a blanket tool denial: preserve both tool policy and resource-level access checks.
- Protect secrets in storage, logs and build contexts. Not all secrets live in
  credbroker; secret settings and bootstrap credentials have separate boundaries.

## Configuration and navigation

Bootstrap defaults/environment configure topology and installation identity;
behavioral settings belong in the PostgreSQL registry. Preserve its declared
scopes, validation and generators. Do not add config.json or parallel runtime
environment overrides for registry-owned behavior.

Use `$PI_RUCLAW_ROOT/profile/areas.md` to find the relevant code and sources;
checks are in `$PI_RUCLAW_ROOT/profile/testing.md`. These files belong to the external
profile, NOT the product checkout. Use the launcher's absolute Area map / Test map
paths with read (it does not expand shell variables). Read the task and applicable
contracts, not the whole documentation tree. Repository CLAUDE/AGENTS,
ADRs, specs and even inline comments may be stale or contradictory; do not bulk-load
them or treat a title/status as authority. Code shows current behavior, not proof
that the behavior is intended. Surface material conflicts instead of guessing.

Before branch/commit/MR operations, read the bundled `git-workflow` skill and the
repository's `docs_flow/pravila-raboty-s-git.md` and `docs_flow/changelog.md` for
those conventions. They are not sources for architecture or secret configuration.
