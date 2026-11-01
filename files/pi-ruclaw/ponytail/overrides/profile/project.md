# RuClaw Pi — project profile (Ponytail experiment)

RuClaw is a corporate agent platform with a Go gateway/runtime/tools, PostgreSQL,
object storage, a separate credential broker, two React frontends and sidecars.

Code-writing policy is the pinned `skills/ponytail/SKILL.md`, level **full**.
Code-review policy is the pinned `skills/ponytail-review/SKILL.md`. Read the relevant
skill in full before doing that work. These REPLACE the default profile's design
and review checklists; do not stack the old architecture/DDD or review methodology
on top. Follow the existing code structure as Ponytail requires.

The original user task, linked applicable contracts and acceptance criteria still
apply. Simplicity is not permission to omit requested behavior. Permissions, secret
protection, isolated resources, honest check results and Git ownership are unchanged.

`$PI_RUCLAW_ROOT/profile/areas.md` is navigation;
`$PI_RUCLAW_ROOT/profile/testing.md` describes commands and execution boundaries,
not additional design policy. Both belong to the external profile, not the product
checkout. Use the launcher's absolute Area map / Test map paths with read; it does
not expand shell variables. Inspect current recipes before executing them.
Read the bundled git-workflow skill and the repository's
`docs_flow/pravila-raboty-s-git.md` and `docs_flow/changelog.md` before Git operations.
Do not bulk-load unrelated team instructions, past solutions or reports.
