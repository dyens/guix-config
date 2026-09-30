#!/usr/bin/env python3
"""Small Jira helper for RuClaw agents.

Reads JIRA_API_TOKEN only from a simple .envrc line:

    export JIRA_API_TOKEN=...

It searches the current worktree first, then the main worktree/common git dir so linked git worktrees can reuse the primary checkout's .envrc.
Never prints the token.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

BASE_URL = os.environ.get("JIRA_BASE_URL", "https://jira.croc.ru").rstrip("/")
ISSUE_RE = re.compile(r"RCL-\d+", re.IGNORECASE)


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
        match = re.match(r"(?:export\s+)?JIRA_API_TOKEN=(.*)", line)
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
    raise SystemExit(f"JIRA_API_TOKEN was not found in any .envrc checked:\n{checked}")


def issue_key(value: str) -> str:
    match = ISSUE_RE.search(value)
    if not match:
        raise SystemExit(f"Could not find RCL issue key in: {value}")
    return match.group(0).upper()


def request(method: str, path: str, *, body: dict[str, Any] | None = None, fail: bool = True) -> Any:
    token = load_token()
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:  # noqa: S310 - internal Jira URL
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        if not fail:
            return None
        raise SystemExit(f"Jira HTTP {exc.code} for {method} {path}: {details}") from exc
    except urllib.error.URLError as exc:
        if not fail:
            return None
        raise SystemExit(f"Jira request failed for {method} {path}: {exc}") from exc


def field_name(value: Any) -> str:
    if value is None:
        return "—"
    if isinstance(value, dict):
        return str(value.get("displayName") or value.get("name") or value.get("value") or value.get("key") or "—")
    return str(value)


def print_issue(key: str, comments: int) -> None:
    issue = request("GET", f"/rest/api/2/issue/{key}")
    fields = issue.get("fields", {})
    print(f"# {issue.get('key', key)}: {fields.get('summary', '')}")
    print()
    print(f"- URL: {BASE_URL}/browse/{issue.get('key', key)}")
    print(f"- Status: {field_name(fields.get('status'))}")
    print(f"- Type: {field_name(fields.get('issuetype'))}")
    print(f"- Priority: {field_name(fields.get('priority'))}")
    print(f"- Assignee: {field_name(fields.get('assignee'))}")
    print(f"- Reporter: {field_name(fields.get('reporter'))}")
    labels = fields.get("labels") or []
    print(f"- Labels: {', '.join(labels) if labels else '—'}")
    print()
    print("## Description")
    print()
    print(fields.get("description") or "—")

    if comments:
        data = request("GET", f"/rest/api/2/issue/{key}/comment?orderBy=-created&maxResults={comments}")
        items = data.get("comments", [])
        print()
        print(f"## Last {len(items)} comments")
        for item in items:
            author = field_name(item.get("author"))
            created = item.get("created", "")
            print()
            print(f"### {author} at {created}")
            print()
            print(item.get("body") or "")


def read_body(args: argparse.Namespace) -> str:
    if args.body:
        return args.body
    if args.file:
        return Path(args.file).read_text(encoding="utf-8")
    if not sys.stdin.isatty():
        return sys.stdin.read()
    raise SystemExit("Provide comment text via --body, --file, or stdin")


def add_comment(key: str, body: str) -> None:
    body = body.strip()
    if not body:
        raise SystemExit("Refusing to post an empty Jira comment")
    result = request("POST", f"/rest/api/2/issue/{key}/comment", body={"body": body})
    print(f"Posted comment {result.get('id', '')} to {BASE_URL}/browse/{key}")


SEARCH_FIELDS = ["summary", "status", "assignee", "issuetype", "priority", "updated"]


def search_data(jql: str, max_results: int, *, fail: bool = True) -> Any:
    return request(
        "POST",
        "/rest/api/2/search",
        body={"jql": jql, "maxResults": max_results, "fields": SEARCH_FIELDS},
        fail=fail,
    )


def print_search_results(issues: list[dict[str, Any]], total: int, jql: str) -> None:
    print(f"# Jira issues ({len(issues)} of {total})")
    print()
    print(f"JQL: `{jql}`")
    print()
    for issue in issues:
        fields = issue.get("fields", {})
        key = issue.get("key", "")
        url = f"{BASE_URL}/browse/{key}"
        print(f"- [{key}]({url}): {fields.get('summary', '')}")
        print(f"  - URL: {url}")
        print(f"  - Status: {field_name(fields.get('status'))}")
        print(f"  - Type: {field_name(fields.get('issuetype'))}")
        print(f"  - Priority: {field_name(fields.get('priority'))}")
        print(f"  - Assignee: {field_name(fields.get('assignee'))}")
        print(f"  - Updated: {fields.get('updated', '—')}")


def search_issues(jql: str, max_results: int) -> None:
    data = search_data(jql, max_results)
    issues = data.get("issues", [])
    print_search_results(issues, data.get("total", len(issues)), jql)


def reviewer_field_names() -> list[str]:
    data = request("GET", "/rest/api/2/field", fail=False)
    if not isinstance(data, list):
        return []
    result: list[str] = []
    needles = ("review", "reviewer", "ревью", "реценз", "провер")
    for field in data:
        name = str(field.get("name", ""))
        if any(needle in name.lower() for needle in needles):
            result.append(name)
    return result


def quote_jql_field(name: str) -> str:
    escaped = name.replace('"', '\\"')
    return f'"{escaped}"'


ACTIVE_RCL_FILTER = "project = RCL AND resolution = Unresolved AND statusCategory != Done"


def search_mine(max_results: int) -> None:
    queries = [f"{ACTIVE_RCL_FILTER} AND assignee = currentUser() ORDER BY updated DESC"]
    for name in reviewer_field_names():
        queries.append(f"{ACTIVE_RCL_FILTER} AND {quote_jql_field(name)} = currentUser() ORDER BY updated DESC")

    by_key: dict[str, dict[str, Any]] = {}
    used_queries: list[str] = []
    for jql in queries:
        data = search_data(jql, max_results, fail=False)
        if not data:
            continue
        used_queries.append(jql)
        for issue in data.get("issues", []):
            by_key[issue.get("key", "")] = issue

    issues = sorted(
        by_key.values(),
        key=lambda issue: issue.get("fields", {}).get("updated", ""),
        reverse=True,
    )[:max_results]
    joined_jql = " OR ".join(f"({jql})" for jql in used_queries) if used_queries else queries[0]
    print_search_results(issues, len(by_key), joined_jql)


def main() -> None:
    parser = argparse.ArgumentParser(description="RuClaw Jira helper")
    sub = parser.add_subparsers(dest="command", required=True)

    read = sub.add_parser("read", help="Print issue summary, description, and optional latest comments")
    read.add_argument("issue", help="RCL-123 or Jira URL")
    read.add_argument("--comments", type=int, default=5, help="Number of latest comments to print (default: 5; 0 disables)")

    comment = sub.add_parser("comment", help="Add a comment to an issue")
    comment.add_argument("issue", help="RCL-123 or Jira URL")
    group = comment.add_mutually_exclusive_group()
    group.add_argument("--body", help="Comment body")
    group.add_argument("--file", help="Read comment body from file")

    mine = sub.add_parser("mine", help="List open RCL issues assigned to or awaiting review from the current Jira user")
    mine.add_argument("--max", type=int, default=50, help="Maximum issues to return (default: 50)")
    mine.add_argument(
        "--jql",
        help="Override JQL. Useful if the local Jira reviewer field has a different name.",
    )
    mine.add_argument(
        "--assignee-only",
        action="store_true",
        help="Only list issues assigned to currentUser(); skips the reviewer clause.",
    )

    args = parser.parse_args()
    if args.command == "mine":
        if args.jql:
            search_issues(args.jql, max(args.max, 1))
        elif args.assignee_only:
            search_issues(f"{ACTIVE_RCL_FILTER} AND assignee = currentUser() ORDER BY updated DESC", max(args.max, 1))
        else:
            search_mine(max(args.max, 1))
        return

    key = issue_key(args.issue)
    if args.command == "read":
        print_issue(key, max(args.comments, 0))
    elif args.command == "comment":
        add_comment(key, read_body(args))


if __name__ == "__main__":
    main()
