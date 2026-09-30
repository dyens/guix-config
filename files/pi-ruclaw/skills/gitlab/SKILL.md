---
name: gitlab
description: "Read RuClaw GitLab merge requests and prepare local diff refs for review. Use when the user passes a gitlab.croc.ru merge request URL or asks to inspect an MR."
---

# GitLab for RuClaw

Use this skill for routine GitLab MR work in RuClaw:

- read MR metadata, description, changed files, and recent notes;
- read a specific MR note from a `#note_<id>` URL;
- fetch MR head into a local read-only remote ref;
- prepare exact diff/log commands for code review;
- post review summaries as MR notes/comments;
- inspect MR CI pipelines, failed jobs, and failed job logs.

GitLab is at `https://gitlab.croc.ru/croc_dit/ruclaw`. Auth uses `GITLAB_TOKEN` from `.envrc` only. Never print or expose the token.

## Helper script

All helper paths below are relative to this skill directory (`gitlab/`). When executing them from another working directory, resolve them against the directory that contains this `SKILL.md`.

Prefer the helper stored next to this skill:

```bash
scripts/gitlab.py mr https://gitlab.croc.ru/croc_dit/ruclaw/-/merge_requests/123 --fetch
scripts/gitlab.py mr 123 --fetch
scripts/gitlab.py note-read 'https://gitlab.croc.ru/croc_dit/ruclaw/-/merge_requests/123#note_456'
scripts/gitlab.py ci 123 --trace
scripts/gitlab.py note 123 --file /tmp/review.md
printf '%s\n' 'Review summary' | scripts/gitlab.py note 123
```

The script:

- accepts full MR URLs or IID numbers;
- reads `GITLAB_TOKEN` from `.envrc`;
- searches `.envrc` across the current worktree and main/common git checkout, so linked worktrees can reuse the primary checkout's token file;
- fetches MR head to `origin/merge-requests/<iid>/head` when `--fetch` is passed;
- prints suggested `git diff <base>...<mr-head-ref>` and `git log <base>..<mr-head-ref>` commands;
- reads one MR note via `note-read <MR-URL#note_id>`;
- inspects latest MR CI via `ci <MR-URL-or-IID>` and can fetch failed job trace tails with `--trace`;
- posts MR notes via the `note` subcommand and prints a direct `Comment URL`.

## Reviewing an MR

When the user runs something like:

```text
/skill:code-review https://gitlab.croc.ru/croc_dit/ruclaw/-/merge_requests/123
```

or asks to review an MR URL:

1. Use this GitLab helper first:

   ```bash
   scripts/gitlab.py mr <MR-URL> --fetch
   ```

2. Use the printed base SHA and MR head ref as the review diff.
3. Identify the originating spec/sub-ticket from:
   - MR description;
   - branch name;
   - commit messages;
   - `docs/specs/` or `.scratch/`.
4. Run the `code-review` skill's two-axis review:
   - Standards axis against RuClaw rules;
   - Spec axis against the found spec/sub-ticket.

Do not checkout or mutate the MR branch unless the user explicitly asks. Fetching `origin/merge-requests/<iid>/head` is enough for read-only review.

## Investigating CI failures

When the user asks to diagnose a broken MR pipeline, run:

```bash
scripts/gitlab.py ci <MR-URL-or-IID> --trace
```

Default output shows failed/canceled/skipped/manual jobs from the latest MR pipeline. Use `--all` to see every job.

Diagnosis loop:

1. Identify failed job names, stages, URLs, and failure reasons.
2. Read the trace tail for the first relevant failed job.
3. Classify the failure:
   - test failure;
   - lint/typecheck/build failure;
   - migration/schema failure;
   - flaky infra/dependency/network;
   - missing CI secret/config;
   - unrelated pipeline failure.
4. Map the failure to the MR diff where possible.
5. Propose the smallest fix and exact local verification command.

Do not retry pipelines, cancel jobs, or push fixes unless the user explicitly asks.

## Posting review comments

After `code-review`, if the user asks to add the review to the MR comment, draft a concise note and normally ask for confirmation unless they explicitly said to post it.

Use:

```bash
scripts/gitlab.py note <MR-URL-or-IID> --file /tmp/review.md
```

After posting, return the printed `Comment URL` to the user.

Recommended note shape:

```markdown
Code review: <short scope>

Standards:
- <finding or "No blockers found">

Spec:
- <finding or "No blockers found">

Checks:
- <commands/evidence, if any>
```

Keep MR comments concise. Put long raw review logs in the chat or local files, not in GitLab, unless the user asks.

## Direct API fallback

If the helper is unsuitable, read the token from `.envrc` without printing it and call GitLab API v4 directly. Prefer the helper for normal MR review work.
