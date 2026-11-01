# RuClaw — navigation only

Follow the task's actual code, callers and tests. Useful entry points:
- Go composition: `main.go`, `cmd/root.go`, `cmd/gateway.go`.
- Runtime/tools: `internal/agent`, `internal/tools`.
- Credential broker: `cmd/credbroker`, `internal/credbroker`.
- Storage: `internal/store/pg`, `internal/objectstore`.
- User UI/API: `ui/user-front`, `internal/userapi`.
- Admin UI: `ui/web`.
- Sidecars: `services`, `playwright-service`.
- Build/deployment: `Makefile`, `scripts`, `docker-compose*.yml`, `deploy`.
- Tests: `tests`, nearby package tests, external `$PI_RUCLAW_ROOT/profile/testing.md`.
  Use the launcher's absolute Test map path with read, not a checkout-relative path
  or a literal shell variable.

This map imposes no architecture, layering or design checklist. Read the original
requirements and applicable contracts; inspect current code instead of importing
old plans or alternate solutions.
