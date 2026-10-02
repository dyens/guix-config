#!/usr/bin/env python3
"""Partition an exact Git diff; fail closed on unknown paths or missing results."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

# First match owns a path. Supplementary reviews may overlap, primary batches may not.
RULES = [
    ("approval", r"(^internal/(approval|core/.*/approval)|approval|amend)",
     "Trace preview → editable patch → authoritative schema → policy → durable decision → execution. Check revisions, retries, audit and provider history."),
    ("chat-runtime", r"^internal/(userfront/|store/.*user_front|gateway/methods/user_chat|agent/|orchestration/|goalrun/)|^cmd/gateway.*user_front",
     "Trace acceptance, persistence, replay, surface closure, queue/drain and cancellation. Enumerate failures between writes and concurrent handoffs; inspect real PG semantics."),
    ("a2ui", r"^internal/(a2ui|chatui)/|^internal/tools/(show_ui|ask_user|surface|result)|^ui/user-front/src/(features/a2ui/|realtime/a2ui)",
     "Trace producer → snapshot → renderer → action. Compare displayed forecast with payload; check 0/1/many, forbidden single items, silent/card-only results, stale versions and keyboard use."),
    ("chat-ui", r"^ui/user-front/src/(features/chat/|realtime/|pages/chat|.*outbox)",
     "Trace composer/outbox, steer, reconnect and terminal events. Separate permanent errors from retryable conflicts; check stale responses, deduplication and recovery UX."),
    ("contracts-artifacts", r"^api/|openapi|/gen/|generated|\.generated\.|lock\.(yaml|json)$|uv\.lock$|package\.json$|contract|testdata|__fixtures__",
     "Trace source → generator → published artifact → consumer. Regenerate authoritatively in an approved environment; distinguish byte equality from generation parity."),
    ("ops-docs", r"^(docs/|docs_flow/|deploy/|charts/|install/|scripts/|\.gitlab|docker-compose|Dockerfile|Makefile)|(^|/)README\.md$|\.md$",
     "Check exact-head CI coverage, rollout/rollback, settings, debt, stated scope and provenance. Missing checks are gaps, not passes."),
    ("backend", r"^(internal/|cmd/|pkg/|migrations/|tests/)|^go\.(mod|sum)$|^main\.go$",
     "Check tenant/authz boundaries, storage, migration compatibility, zero/nullable values and negative paths. Follow callers and callees outside your assigned diff where needed."),
    ("frontend", r"^ui/",
     "Check actual rendered behavior, data/action consistency, state transitions, keyboard/focus, frontend boundaries and build/runtime contracts."),
    ("services", r"^services/",
     "Check worker deadlines, retries, durable delivery, typed errors, health and service packaging boundaries."),
]


def git(*args):
    return subprocess.check_output(["git", *args])


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def snapshot(bundle):
    metadata = dict(line.split("=", 1) for line in
                    (bundle / "metadata.txt").read_text().splitlines() if "=" in line)
    base, head = metadata["base_sha"], metadata["head_sha"]
    for sha in (base, head):
        if not re.fullmatch(r"[0-9a-f]{40,64}", sha):
            raise ValueError("Expected exact commit SHAs in metadata")
        if git("rev-parse", "--verify", sha + "^{commit}").decode().strip() != sha:
            raise ValueError("Snapshot is not a commit")
    if git("merge-base", base, head).decode().strip() != metadata["merge_base"]:
        raise ValueError("Merge-base does not match metadata")
    paths = git("diff", "--name-only", "--no-renames", "-z", f"{base}...{head}").decode().split("\0")[:-1]
    if not paths:
        raise ValueError("Empty diff")
    if any("\n" in p or "\t" in p for p in paths):
        raise ValueError("Newline/tab filenames require a separately audited bundle")
    # --no-renames treats both sides of renames as explicit coverage obligations.
    return base, head, paths


def prepare(args):
    bundle = args.bundle.resolve()
    base, head, paths = snapshot(bundle)
    rules = RULES
    if args.rules:
        rules = [(r["lane"], r["pattern"], r["brief"]) for r in json.loads(args.rules.read_text())]
    compiled = []
    for lane, pattern, brief in rules:
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", lane):
            raise ValueError("Unsafe lane name")
        compiled.append((lane, re.compile(pattern), brief))
    assignments, unknown = {}, []
    for path in paths:
        match = next(((lane, brief) for lane, rx, brief in compiled if rx.search(path)), None)
        if match is None:
            unknown.append(path)
        else:
            lane, brief = match
            assignments.setdefault(lane, (brief, []))[1].append(path)
    (bundle / "unassigned.txt").write_text("".join(p + "\n" for p in unknown))
    if unknown:
        raise ValueError(f"{len(unknown)} unassigned paths; inspect unassigned.txt and supply --rules. Preparation BLOCKED")
    lanes = bundle / "lanes"
    if lanes.exists():
        raise ValueError("lanes/ already exists; use a fresh bundle (never reuse stale results)")
    lanes.mkdir()
    batches = []
    for lane, (brief, members) in assignments.items():
        groups, current, lines, size = [], [], 0, 0
        for path in members:
            patch = git("diff", "--no-ext-diff", "--no-textconv", "--no-renames", f"{base}...{head}", "--", path)
            count = patch.count(b"\n")
            if current and (len(current) >= args.max_files or lines + count > args.max_lines or size + len(patch) > args.max_bytes):
                groups.append(current)
                current, lines, size = [], 0, 0
            current.append(path)
            lines += count
            size += len(patch)
        if current:
            groups.append(current)
        for i, group in enumerate(groups, 1):
            name = f"{lane}-{i:02d}"
            directory = lanes / name
            directory.mkdir()
            (directory / "files.txt").write_text("".join(p + "\n" for p in group))
            for filename, context in (("diff.patch", "3"), ("diff-u80.patch", "80")):
                (directory / filename).write_bytes(git("diff", "--no-ext-diff", "--no-textconv", "--no-renames", f"--unified={context}", f"{base}...{head}", "--", *group))
            patch = (directory / "diff.patch").read_bytes()
            oversized = len(patch) > args.max_bytes or patch.count(b"\n") > args.max_lines
            (directory / "brief.md").write_text(
                f"# {name}\n\nRange: {base}...{head}\n\n{brief}\n\n"
                "Review standards, full spec and correctness/negative paths. Trace related callers/callees at head-tree even outside this batch. "
                "Report invariants, counterexamples, evidence and checks not run; never infer a pass from existing tests.\n"
                + ("\nOversized indivisible file: allocate a dedicated semantic pass; do not truncate.\n" if oversized else ""))
            hashes = {f: digest(directory / f) for f in ("files.txt", "diff.patch", "diff-u80.patch", "brief.md")}
            batches.append({"id": name, "lane": lane, "paths": group, "oversized": oversized, "sha256": hashes})
    dump(bundle / "coverage.json", {"base": base, "head": head, "paths": paths, "batches": batches})
    dump(bundle / "results.template.json", {b["id"]: {"status": "pending", "report": f"reports/{b['id']}.md"} for b in batches})
    print(f"Coverage PASS: {len(paths)}/{len(paths)} paths, {len(batches)} batches. Results still PENDING.")


def validate(args):
    bundle = args.bundle.resolve()
    base, head, paths = snapshot(bundle)
    manifest = json.loads((bundle / "coverage.json").read_text())
    if (manifest["base"], manifest["head"], manifest["paths"]) != (base, head, paths):
        raise ValueError("Coverage snapshot mismatch")
    assigned, ids = [], set()
    for batch in manifest["batches"]:
        name = batch["id"]
        if not re.fullmatch(r"[a-z0-9-]+", name) or name in ids:
            raise ValueError("Unsafe/duplicate batch ID")
        ids.add(name)
        directory = bundle / "lanes" / name
        assigned.extend(batch["paths"])
        if (directory / "files.txt").read_text().splitlines() != batch["paths"]:
            raise ValueError(f"File list mismatch: {name}")
        for file in ("files.txt", "diff.patch", "diff-u80.patch", "brief.md"):
            if digest(directory / file) != batch["sha256"][file]:
                raise ValueError(f"Batch evidence changed: {name}/{file}")
    if len(assigned) != len(set(assigned)) or set(assigned) != set(paths):
        raise ValueError("Duplicate or missing primary assignments")
    if not args.results:
        print(f"Coverage PASS: {len(paths)} paths, {len(ids)} batches; completion NOT checked")
        return
    results = json.loads(args.results.read_text())
    if set(results) != ids:
        raise ValueError("Results must contain exactly all primary batch IDs")
    gaps = []
    for name, result in results.items():
        status = result.get("status")
        if status not in ("reviewed", "gap"):
            raise ValueError(f"Unfinished batch: {name}")
        report = (bundle / result["report"]).resolve()
        if not report.is_relative_to(bundle) or not report.is_file() or not report.read_text().strip():
            raise ValueError(f"Missing/unsafe/empty report: {name}")
        if status == "gap":
            if not result.get("reason", "").strip():
                raise ValueError(f"Gap needs a reason: {name}")
            gaps.append(name)
    if gaps:
        raise ValueError("REVIEW INCONCLUSIVE; explicit gaps: " + ", ".join(gaps))
    print("Completion PASS: every batch has a report. Not proof of correctness or CI readiness.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--rules", type=Path, help="JSON list of ordered {lane, pattern, brief} rules; replaces defaults")
    parser.add_argument("--max-files", type=int, default=12)
    parser.add_argument("--max-lines", type=int, default=800)
    parser.add_argument("--max-bytes", type=int, default=65536)
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--results", type=Path, help="Validate completion using this results JSON")
    args = parser.parse_args()
    if min(args.max_files, args.max_lines, args.max_bytes) <= 0:
        parser.error("Batch limits must be positive")
    try:
        if args.validate or args.results:
            validate(args)
        else:
            prepare(args)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as exc:
        print(f"BLOCKED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
