#!/usr/bin/env python3
"""Small GitLab helper for RuClaw agents.

Reads GITLAB_TOKEN only from .envrc. It searches the current worktree first,
then the main worktree/common git checkout so linked git worktrees can reuse the
primary checkout's .envrc. Never prints the token.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

BASE_URL = "https://gitlab.croc.ru"
DEFAULT_PROJECT = "croc_dit/ruclaw"
MR_URL_RE = re.compile(r"gitlab\.croc\.ru/(?P<project>.+?)/-/merge_requests/(?P<iid>\d+)")
NOTE_RE = re.compile(r"#note_(?P<note_id>\d+)")


def run_git(args: list[str]) -> str | None:
    try:
        result = subprocess.run(
            ["git", *args],
            check=True,
            cwd=Path.cwd(),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return result.stdout.strip()


def envrc_candidates() -> list[Path]:
    candidates: list[Path] = []
    seen: set[Path] = set()

    def add(path: Path) -> None:
        resolved = path.expanduser().resolve()
        if resolved not in seen:
            seen.add(resolved)
            candidates.append(resolved)

    cur = Path.cwd().resolve()
    for path in [cur, *cur.parents]:
        add(path / ".envrc")

    common_dir = run_git(["rev-parse", "--path-format=absolute", "--git-common-dir"])
    if common_dir:
        common = Path(common_dir)
        if common.name == ".git":
            add(common.parent / ".envrc")

    worktrees = run_git(["worktree", "list", "--porcelain"])
    if worktrees:
        for line in worktrees.splitlines():
            if line.startswith("worktree "):
                add(Path(line.removeprefix("worktree ")) / ".envrc")

    return candidates


def token_from_envrc(path: Path) -> str | None:
    if not path.exists():
        return None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.match(r"(?:export\s+)?GITLAB_TOKEN=(.*)", line)
        if not match:
            continue
        value = match.group(1).strip()
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        if value:
            return value
    return None


def load_token() -> str:
    for envrc in envrc_candidates():
        token = token_from_envrc(envrc)
        if token:
            return token
    checked = "\n".join(f"- {path}" for path in envrc_candidates())
    raise SystemExit(f"GITLAB_TOKEN was not found in any .envrc checked:\n{checked}")


def parse_mr(value: str, default_project: str) -> tuple[str, int]:
    match = MR_URL_RE.search(value)
    if match:
        return urllib.parse.unquote(match.group("project")), int(match.group("iid"))
    if value.isdigit():
        return default_project, int(value)
    raise SystemExit(f"Could not parse GitLab MR URL or IID: {value}")


def parse_mr_note(value: str, default_project: str) -> tuple[str, int, int]:
    project, iid = parse_mr(value, default_project)
    match = NOTE_RE.search(value)
    if not match:
        raise SystemExit(f"Could not parse GitLab note anchor '#note_<id>' from: {value}")
    return project, iid, int(match.group("note_id"))


def project_id(project: str) -> str:
    return urllib.parse.quote(project, safe="")


def request(path: str, *, method: str = "GET", body: dict[str, Any] | None = None) -> Any:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE_URL}/api/v4{path}",
        data=data,
        method=method,
        headers={"PRIVATE-TOKEN": load_token(), "Accept": "application/json", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:  # noqa: S310 - internal GitLab URL
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"GitLab HTTP {exc.code} for {path}: {details}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"GitLab request failed for {path}: {exc}") from exc


def fetch_mr(iid: int) -> None:
    ref = f"refs/merge-requests/{iid}/head:refs/remotes/origin/merge-requests/{iid}/head"
    subprocess.run(["git", "fetch", "origin", ref], check=True)


def name(user: Any) -> str:
    if isinstance(user, dict):
        return str(user.get("name") or user.get("username") or "—")
    return "—"


def read_body(args: argparse.Namespace) -> str:
    if args.body:
        return args.body
    if args.file:
        return Path(args.file).read_text(encoding="utf-8")
    if not sys.stdin.isatty():
        return sys.stdin.read()
    raise SystemExit("Provide note text via --body, --file, or stdin")


def add_mr_note(value: str, body: str, default_project: str) -> None:
    project, iid = parse_mr(value, default_project)
    body = body.strip()
    if not body:
        raise SystemExit("Refusing to post an empty GitLab MR note")
    encoded = project_id(project)
    result = request(f"/projects/{encoded}/merge_requests/{iid}/notes", method="POST", body={"body": body})
    note_id = result.get("id", "")
    mr_url = f"{BASE_URL}/{project}/-/merge_requests/{iid}"
    note_url = f"{mr_url}#note_{note_id}" if note_id else mr_url
    print(f"Posted note {note_id} to {mr_url}")
    print(f"Comment URL: {note_url}")


def print_job(job: dict[str, Any]) -> None:
    print(f"- {job.get('name', '')} [{job.get('status', '')}]")
    print(f"  - Stage: {job.get('stage', '—')}")
    print(f"  - URL: {job.get('web_url', '—')}")
    print(f"  - Runner: {name(job.get('runner'))}")
    print(f"  - Duration: {job.get('duration', '—')}")
    failure = job.get("failure_reason")
    if failure:
        print(f"  - Failure reason: {failure}")


def print_ci(value: str, default_project: str, failed_only: bool, trace: bool, trace_limit: int) -> None:
    project, iid = parse_mr(value, default_project)
    encoded = project_id(project)
    mr = request(f"/projects/{encoded}/merge_requests/{iid}")
    pipelines = request(f"/projects/{encoded}/merge_requests/{iid}/pipelines?per_page=10") or []
    print(f"# CI for MR !{iid}: {mr.get('title', '')}")
    print()
    print(f"- MR URL: {mr.get('web_url', BASE_URL)}")
    if not pipelines:
        print("- No MR pipelines found.")
        return

    pipeline = pipelines[0]
    pipeline_id = pipeline.get("id")
    print(f"- Pipeline: {pipeline.get('web_url', '—')}")
    print(f"- Status: {pipeline.get('status', '—')}")
    print(f"- Ref: {pipeline.get('ref', '—')}")
    print(f"- SHA: {pipeline.get('sha', '—')}")
    print()

    jobs = request(f"/projects/{encoded}/pipelines/{pipeline_id}/jobs?per_page=100") or []
    if failed_only:
        jobs = [job for job in jobs if job.get("status") in {"failed", "canceled", "skipped", "manual"}]
    print("## Jobs")
    print()
    for job in jobs:
        print_job(job)

    failed_jobs = [job for job in jobs if job.get("status") == "failed"]
    if trace and failed_jobs:
        print()
        print("## Failed job traces")
        for job in failed_jobs:
            job_id = job.get("id")
            print()
            print(f"### {job.get('name', '')} ({job_id})")
            print()
            req = urllib.request.Request(
                f"{BASE_URL}/api/v4/projects/{encoded}/jobs/{job_id}/trace",
                headers={"PRIVATE-TOKEN": load_token(), "Accept": "text/plain"},
            )
            try:
                with urllib.request.urlopen(req, timeout=30) as resp:  # noqa: S310 - internal GitLab URL
                    raw = resp.read().decode("utf-8", errors="replace")
            except urllib.error.HTTPError as exc:
                raw = f"<failed to fetch trace: HTTP {exc.code}>"
            print(raw[-trace_limit:])


def print_mr_note(value: str, default_project: str) -> None:
    project, iid, note_id = parse_mr_note(value, default_project)
    encoded = project_id(project)
    mr = request(f"/projects/{encoded}/merge_requests/{iid}")
    note = request(f"/projects/{encoded}/merge_requests/{iid}/notes/{note_id}")
    print(f"# MR !{iid} note {note_id}: {mr.get('title', '')}")
    print()
    print(f"- MR URL: {mr.get('web_url', BASE_URL)}")
    print(f"- Comment URL: {mr.get('web_url', BASE_URL)}#note_{note_id}")
    print(f"- Project: {project}")
    print(f"- Author: {name(note.get('author'))}")
    print(f"- Created: {note.get('created_at', '—')}")
    print(f"- Updated: {note.get('updated_at', '—')}")
    print(f"- Resolvable: {note.get('resolvable', False)}")
    print(f"- Resolved: {note.get('resolved', False)}")
    print()
    print("## Note body")
    print()
    print(note.get("body") or "")


def print_mr(value: str, comments: int, fetch: bool, default_project: str) -> None:
    project, iid = parse_mr(value, default_project)
    encoded = project_id(project)
    mr = request(f"/projects/{encoded}/merge_requests/{iid}")
    changes = request(f"/projects/{encoded}/merge_requests/{iid}/changes")

    if fetch:
        fetch_mr(iid)

    diff_refs = mr.get("diff_refs") or {}
    head_ref = f"origin/merge-requests/{iid}/head" if fetch else mr.get("source_branch", "")
    fixed_point = diff_refs.get("base_sha") or mr.get("target_branch", "")

    print(f"# MR !{iid}: {mr.get('title', '')}")
    print()
    print(f"- URL: {mr.get('web_url', BASE_URL)}")
    print(f"- Project: {project}")
    print(f"- State: {mr.get('state', '—')}")
    print(f"- Source: {mr.get('source_branch', '—')}")
    print(f"- Target: {mr.get('target_branch', '—')}")
    print(f"- Author: {name(mr.get('author'))}")
    print(f"- Assignee: {name(mr.get('assignee'))}")
    reviewers = ", ".join(name(user) for user in mr.get("reviewers", [])) or "—"
    print(f"- Reviewers: {reviewers}")
    print(f"- Labels: {', '.join(mr.get('labels') or []) or '—'}")
    print(f"- Base SHA: {diff_refs.get('base_sha', '—')}")
    print(f"- Head SHA: {diff_refs.get('head_sha', mr.get('sha', '—'))}")
    print()
    print("## Local review refs")
    print()
    if fetch:
        print(f"- MR head ref: `{head_ref}`")
        print(f"- Suggested diff: `git diff {fixed_point}...{head_ref}`")
        print(f"- Suggested log: `git log --oneline {fixed_point}..{head_ref}`")
    else:
        print("- Run with `--fetch` to fetch `origin/merge-requests/<iid>/head` and print local diff commands.")
    print()
    print("## Description")
    print()
    print(mr.get("description") or "—")
    print()
    print("## Changed files")
    print()
    for change in changes.get("changes", []):
        old = change.get("old_path")
        new = change.get("new_path")
        marker = ""
        if change.get("new_file"):
            marker = " added"
        elif change.get("deleted_file"):
            marker = " deleted"
        elif change.get("renamed_file"):
            marker = f" renamed from {old}"
        print(f"- `{new}`{marker}")

    if comments:
        notes = request(
            f"/projects/{encoded}/merge_requests/{iid}/notes?sort=desc&order_by=created_at&per_page={comments}"
        )
        print()
        print(f"## Last {len(notes)} notes")
        for note in notes:
            if note.get("system"):
                continue
            print()
            print(f"### {name(note.get('author'))} at {note.get('created_at', '')}")
            print()
            print(note.get("body") or "")


def main() -> None:
    parser = argparse.ArgumentParser(description="RuClaw GitLab helper")
    sub = parser.add_subparsers(dest="command", required=True)

    mr = sub.add_parser("mr", help="Print MR metadata, changed files, and optional notes")
    mr.add_argument("mr", help="MR IID or full GitLab MR URL")
    mr.add_argument("--project", default=DEFAULT_PROJECT, help=f"Project path for IID input (default: {DEFAULT_PROJECT})")
    mr.add_argument("--comments", type=int, default=10, help="Number of latest MR notes to print (default: 10; 0 disables)")
    mr.add_argument("--fetch", action="store_true", help="Fetch origin/merge-requests/<iid>/head for local review")

    note = sub.add_parser("note", help="Add a note/comment to an MR")
    note.add_argument("mr", help="MR IID or full GitLab MR URL")
    note.add_argument("--project", default=DEFAULT_PROJECT, help=f"Project path for IID input (default: {DEFAULT_PROJECT})")
    group = note.add_mutually_exclusive_group()
    group.add_argument("--body", help="Note body")
    group.add_argument("--file", help="Read note body from file")

    note_read = sub.add_parser("note-read", help="Read one MR note from a URL with #note_<id>")
    note_read.add_argument("url", help="Full GitLab MR note URL ending in #note_<id>")
    note_read.add_argument("--project", default=DEFAULT_PROJECT, help=f"Project path for IID input fallback (default: {DEFAULT_PROJECT})")

    ci = sub.add_parser("ci", help="Inspect latest MR pipeline and jobs")
    ci.add_argument("mr", help="MR IID or full GitLab MR URL")
    ci.add_argument("--project", default=DEFAULT_PROJECT, help=f"Project path for IID input (default: {DEFAULT_PROJECT})")
    ci.add_argument("--all", action="store_true", help="Show all jobs, not only failed/canceled/skipped/manual jobs")
    ci.add_argument("--trace", action="store_true", help="Fetch tail of failed job traces")
    ci.add_argument("--trace-limit", type=int, default=12000, help="Characters of each failed trace tail to print (default: 12000)")

    args = parser.parse_args()
    if args.command == "mr":
        print_mr(args.mr, max(args.comments, 0), args.fetch, args.project)
    elif args.command == "note":
        add_mr_note(args.mr, read_body(args), args.project)
    elif args.command == "note-read":
        print_mr_note(args.url, args.project)
    elif args.command == "ci":
        print_ci(args.mr, args.project, failed_only=not args.all, trace=args.trace, trace_limit=max(args.trace_limit, 1000))


if __name__ == "__main__":
    main()
