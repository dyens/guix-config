# Default implementation workflow: structured tasks

When the user authorizes implementation in this RuClaw profile, read
PI_RUCLAW_ROOT/skills/implement/SKILL.md and use that process, even if the request
was plain text rather than /skill:implement. Do not start implementation from an
advisory question, review-only request or unresolved task scope.

After intake, before product edits, call task_plan with the task contract and steps.
Extension owns statuses and generated plan.md; task_complete saves a short handoff
and advances/reset context atomically. No routine report files, progress diary,
manual Markdown statuses or mandatory rereads after transitions. Read only missing/
stale relevant inputs; use task_get(id) for specific archived detail when needed.
Final independent ruclaw-plan-reviewer remains mandatory. Only parent writes product code.
/task_get_status is a human-only command: Tasks: done/total. Plan: path; no LLM call.
Standing USER permission for implement: ordinary local commits of task-owned changes
on the agreed task branch, and local Docker/Compose for isolated task-owned stands
and dependencies. Do not ask again within these bounds; record this authority in the
plan. Explicit task-specific restrictions/revocations override defaults. Push/MR,
branch switching/history rewriting, shared/prod changes, global prune, volume deletion,
persistent-data resets and privileged/security-bypass operations need separate authority.
See implement's Standing implement permissions for exact bounds; tools alone grant none.
Existing structured tasks resume the injected current step; existing Markdown v2
sessions keep their old tools until explicit handoff. Separate tasks after an agreed endpoint use a fresh session + compact handoff,
not an ever-growing old plan/base; settle children and make the previous writer idle.
Cheap applicable CI-preflight precedes final review; heavy checks may overlap static
review on the same fixed candidate with isolated resources. All required gates still
apply. Legacy sessions require explicit --legacy-cycles recovery, not new onboarding.
