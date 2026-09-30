---
name: code-review
description: "Review a RuClaw diff since a fixed point along two axes: repo standards and spec conformance. Uses parallel subagents when available."
---

# Code Review for RuClaw

Review a local diff or GitLab MR on two separate axes.

Default local form, only when the branch under review is currently checked out:

```bash
git diff <review-base>...HEAD
```

Do **not** blindly use `HEAD`. Pick the correct head for the thing being reviewed:

- checked-out local feature branch: `HEAD` is OK;
- GitLab MR: use fetched MR ref `origin/merge-requests/<iid>/head`;
- another local/remote branch: use that branch/ref explicitly.

Pick the correct base too:

- full feature/MR review: merge-base with the target branch, usually `origin/develop`, or GitLab MR `base_sha`;
- first sub-ticket on a fresh branch: `origin/develop`;
- later sub-ticket review: previous pushed feature-branch tip, usually `origin/<feature-branch>`;
- hotfix/release work: the actual target branch/ref, not `origin/develop` by habit.

Always use three-dot diff (`<base>...<head>`) so Git compares from the merge-base / fixed base to the reviewed head.

GitLab MR form: when the user passes a `gitlab.croc.ru/.../-/merge_requests/<iid>` URL, use the GitLab skill/helper to fetch the MR head and review:

```bash
git diff <base-sha>...origin/merge-requests/<iid>/head
```

1. **Standards**: does the change follow RuClaw/project standards?
2. **Spec**: does the change implement the referenced spec/sub-ticket and avoid scope creep?

## Subagents

Yes: this skill is intended to run two independent subagents in parallel, one per axis, so their contexts and priorities do not pollute each other.

In Pi, if subagent tools are not yet available, call `subagents_enable` and continue once the tools are available.

**Do not assume a reviewer subagent can run git.** Before launching subagents, either:

1. verify the selected agent has shell/git access; or
2. build a parent-verified evidence bundle and pass it to read-only reviewers.

If neither is possible, do the review in the parent session. Do not let a subagent silently review the working tree, the current MR ref, or another head when the requested snapshot is different.

Recommended agents:

- exact-snapshot review with git needed: use an agent with `bash` (`delegate`, `claude-code`, or another shell-capable reviewer), or run the git/evidence phase in the parent;
- artifact-only independent critique: `reviewer` is OK only after the parent has produced the evidence bundle below.

If subagents cannot be used, fall back to doing the two reviews sequentially and clearly say that no subagents were used.

## Inputs

Helper paths below are relative to this skill directory (`code-review/`); `../gitlab/scripts/gitlab.py` is relative to `code-review/` as a sibling skill. When executing from another working directory, resolve these paths against this `SKILL.md` directory.

The user should provide either:

- local review input: fixed point plus optional spec source;
- GitLab MR URL plus optional spec source.

For local review, fixed point is a commit, branch, tag, or ref.
For MR review, run:

```bash
../gitlab/scripts/gitlab.py mr <MR-URL> --fetch
```

Then use the printed base SHA and `origin/merge-requests/<iid>/head` as the diff endpoints.

If fixed point/MR URL is missing, ask for it.
If spec is missing, try to infer it from MR description, branch name, commit messages, and `docs/specs/` / `.scratch/`; otherwise ask.

## RuClaw base/head rules

Use the reviewed change's real target and real head, not a hard-coded `HEAD`.

- Full MR review: fetch MR metadata and use GitLab `base_sha` as base, `origin/merge-requests/<iid>/head` as head.
- Full local feature branch review into develop: `origin/develop...HEAD` if the feature branch is checked out.
- First sub-ticket on a fresh branch: `origin/develop...HEAD`.
- Later sub-tickets after previous work was pushed: `origin/<feature-branch>...HEAD`.
- Reviewing another branch without checking it out: `git diff <base>...<branch-or-ref>`.
- Use three-dot diff: `git diff <base>...<head>`.

## Preflight

Before reviewing:

1. Resolve the diff endpoints:
   - local checked-out branch: `<review-base>` and `HEAD`;
   - local/remote branch not checked out: `<review-base>` and `<branch-or-ref>`;
   - MR URL: `<base-sha>` and `origin/merge-requests/<iid>/head` from the GitLab helper.
2. If a user asks for a historical commit or note snapshot, fetch/verify that exact commit. If the MR ref has moved, review the explicit commit, not the current MR head.
3. If using remote branches, `git fetch` first.
4. Run `git rev-parse` for both endpoints and record exact SHAs.
5. Run `git merge-base <base> <head>` and record it. If it is not `<base>` for an intended three-dot review, confirm the base is still right.
6. Run `git diff --stat <base>...<head>` and ensure the diff is non-empty.
7. Capture commits with `git log <base>..<head> --oneline`. Read with caution when `<base>` is a branch rather than an exact base SHA; the diff remains authoritative.
8. Capture changed files with `git diff --name-only <base>...<head>`.
9. Read the spec/sub-ticket.
10. Identify standards sources, including:
    - `AGENTS.md` files;
    - `docs/agents/workflow.md` if workflow-related;
    - relevant README/docs near touched code;
    - package-specific config and conventions.

## Evidence bundle for subagents

When using subagents that might not have git/shell access, the parent must create an exact-snapshot bundle before launch. Prefer `.scratch/reviews/<ticket-or-mr>/<head-short>/`.

Use the helper when available:

```bash
scripts/prepare-review-bundle.sh <base> <head> .scratch/reviews/<id>/<head-short>
```

It creates:

- `metadata.txt` with exact refs, SHAs, and merge-base;
- `stat.txt`;
- `commits.txt`;
- `files.txt`;
- `diff.patch`;
- `diff-u80.patch`;
- `head-tree/`, a detached worktree at `<head>`.

Equivalent manual commands:

```bash
mkdir -p .scratch/reviews/<id>/<head-short>
git diff --stat <base>...<head> > .scratch/reviews/<id>/<head-short>/stat.txt
git log --oneline <base>..<head> > .scratch/reviews/<id>/<head-short>/commits.txt
git diff --name-only <base>...<head> > .scratch/reviews/<id>/<head-short>/files.txt
git diff --find-renames --find-copies <base>...<head> > .scratch/reviews/<id>/<head-short>/diff.patch
git diff --find-renames --find-copies --unified=80 <base>...<head> > .scratch/reviews/<id>/<head-short>/diff-u80.patch
git worktree add --detach .scratch/reviews/<id>/<head-short>/head-tree <head>
```

For large diffs, also split the patch into path/topic batches and tell each subagent which batch(es) are authoritative. Use the lane helper when available:

```bash
scripts/prepare-review-lanes.sh .scratch/reviews/<id>/<head-short>
```

Default lanes:

- `tenant-theme`: end-to-end tenant theme/settings contract, tenant switch/logout/stale data;
- `design-contrast`: design tokens, generated CSS, runtime variables, WCAG contrast, brand assets/bootstrap;
- `accessibility-components`: keyboard navigation, focus visibility, ARIA, visible state, dialogs/chat/file UX;
- `go-settings-api`: Go settings/API/authz/tenant correctness and tests;
- `generated-parity`: generated OpenAPI/clients/docs/lockfiles and fragile parity checks;
- `ops-readiness`: CI/release/bundle/provenance/rollback/security readiness.

For broad MRs, prefer a three-level review:

1. topic lanes above, each with a focused brief;
2. final synthesis from lane outputs;
3. optional GitLab-ready comment draft.

Pass subagents:

- exact `base`, `head`, and merge-base SHAs;
- paths to `stat.txt`, `commits.txt`, `files.txt`, `diff.patch`, `diff-u80.patch`, spec, and `head-tree` if created;
- instruction: findings must cite the evidence bundle or `head-tree`, and must not use the live working tree as evidence.

If a subagent reports that it cannot inspect the exact bundle, treat that lane as infrastructure failure and review that axis in the parent; do not publish “no findings” from an uninspected diff.

## Lane review briefs

Use these focused prompts for large diffs before final synthesis:

- **tenant-theme**: trace registry/storage/API/generated clients/frontend/tests end-to-end. Look for write/read contracts that are exposed but not applied, tenant switch/logout stale theme, hidden UI with still-live API, and backward-compatible handling of existing settings.
- **design-contrast**: compare token generator checks with actually rendered CSS variables/components. Treat accessibility claims (WCAG, focus, keyboard, contrast) as contracts: verify the published colors/styles, not only source tokens.
- **accessibility-components**: exercise mental keyboard/focus flows. Check `aria-*` is paired with visible focus/active state and that tests assert user-visible behavior, not only attributes.
- **go-settings-api**: check tenant scoping, authz, nullable/zero-value semantics, row locking/merge behavior, generated contract compatibility, and registry docs/tests.
- **generated-parity**: verify generated artifacts match source of truth; look for tests that parse by accident (regex first-match, stale generated files, lockfile drift).
- **ops-readiness**: check whether CI actually covers changed behavior, whether visual/browser checks are mandatory, and whether rollback/provenance notes cover irreversible user-visible changes.

## Standards axis brief

Review only the diff. Report:

- documented-standard violations, citing the standard file/rule;
- security, compatibility, data-loss, multi-tenant, migration, concurrency, performance, or testability risks;
- judgement-call smells only when actionable and not already covered by tooling.

Smell baseline:

- Mysterious Name
- Duplicated Code
- Feature Envy
- Data Clumps
- Primitive Obsession
- Repeated Switches
- Shotgun Surgery
- Divergent Change
- Speculative Generality
- Message Chains
- Middle Man
- Refused Bequest

Keep findings concrete: file/path, hunk or symbol, impact, suggested fix.

## Spec axis brief

Review only the diff against the spec/sub-ticket. Report:

- requested behaviour missing or partial;
- behaviour added but not requested;
- implementation that appears to satisfy the text but is likely wrong;
- acceptance criteria not covered by tests.

Quote or reference the relevant spec/acceptance criterion.

## Synthesis

After lane/subagent reviews, do a parent-session synthesis before returning or posting. The synthesis is not another broad review from scratch; it is an evidence-checking editor pass over lane outputs.

Synthesis duties:

1. Read all lane outputs and the bundle `metadata.txt` / `stat.txt`.
2. Deduplicate findings that describe the same root cause.
3. Normalize severity:
   - **high/blocker**: correctness, security, data loss, tenant isolation, public contract break, accessibility claim violation in shipped default UI, merge/readiness blocker;
   - **medium**: user-visible defect, fragile test that can hide realistic drift, stale API/helper that can break future callers;
   - **low**: cleanup, provenance, documentation, weak non-blocking test coverage.
4. Drop findings that are not sufficiently evidenced by the bundle/head tree.
5. Preserve lane evidence: each final finding must cite concrete files/symbols and impact.
6. Separate merge-blocking findings from non-blocking notes.
7. Record review gaps: lanes not run, checks not run, visual/browser/external gates not verified.
8. State whether subagents were used, which lanes ran, and whether any lane had infrastructure failure.

Recommended synthesis prompt:

```text
You are synthesizing code-review lane outputs, not re-reviewing from scratch.
Inputs: bundle metadata/stat, lane outputs, optional spec/MR description.
Deduplicate, normalize severity, discard weak claims, and produce a concise MR-ready review.
Keep only actionable findings with file/path evidence, impact, and smallest fix.
Do not invent findings that are not supported by a lane output or direct parent evidence.
```

## Aggregation format

For small reviews without lanes, return:

```markdown
## Standards

<findings or "No findings.">

## Spec

<findings or "No findings.">

## Summary

- Standards findings: <n>; worst: <short>
- Spec findings: <n>; worst: <short>
- Subagents: used / not used
```

For lane-based reviews, return:

```markdown
## Итог

<MERGE / DO NOT MERGE / REVIEW INCONCLUSIVE> — <one-line reason>

## Блокирующие замечания

1. **[high] <title>** — `<primary path>`
   - Evidence: <paths/symbols/behavior>
   - Impact: <why it matters>
   - Suggested fix: <smallest acceptable fix>

## Неблокирующие замечания

1. **[medium|low] <title>** — `<primary path>`
   - Evidence: ...
   - Impact: ...
   - Suggested fix: ...

## Проверено

- Range: `<base>...<head>`; merge-base `<sha>`
- Bundle: `<path>`
- Lanes: `<lane list>`
- Checks run / not run: `<commands or gaps>`
- Subagents: used / not used; infrastructure failures: `<none/list>`
```

Do not fix findings unless the user asks.

## Posting to GitLab MR

If the review target is a GitLab MR and the user asks to add the review as an MR comment, prepare a concise Markdown note and post it with:

```bash
../gitlab/scripts/gitlab.py note <MR-URL-or-IID> --file /tmp/review.md
```

Normally show the draft before posting unless the user explicitly instructed to post. Keep the note short: summary, Standards findings, Spec findings, checks/evidence. After posting, return the `Comment URL` printed by the GitLab helper.
