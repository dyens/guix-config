#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: prepare-review-bundle.sh <base> <head> <out-dir>

Creates an exact-snapshot evidence bundle for code review subagents:
  stat.txt, commits.txt, files.txt, diff.patch, diff-u80.patch, metadata.txt,
  and a detached head-tree worktree.
USAGE
}

if [[ $# -ne 3 ]]; then
  usage
  exit 2
fi

base_ref=$1
head_ref=$2
out_dir=$3

base_sha=$(git rev-parse --verify "${base_ref}^{commit}")
head_sha=$(git rev-parse --verify "${head_ref}^{commit}")
merge_base=$(git merge-base "$base_sha" "$head_sha")

mkdir -p "$out_dir"

{
  printf 'base_ref=%s\n' "$base_ref"
  printf 'head_ref=%s\n' "$head_ref"
  printf 'base_sha=%s\n' "$base_sha"
  printf 'head_sha=%s\n' "$head_sha"
  printf 'merge_base=%s\n' "$merge_base"
  printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$out_dir/metadata.txt"

git diff --stat "$base_sha...$head_sha" > "$out_dir/stat.txt"
git log --oneline "$base_sha..$head_sha" > "$out_dir/commits.txt"
git diff --name-only "$base_sha...$head_sha" > "$out_dir/files.txt"
git diff --find-renames --find-copies "$base_sha...$head_sha" > "$out_dir/diff.patch"
git diff --find-renames --find-copies --unified=80 "$base_sha...$head_sha" > "$out_dir/diff-u80.patch"

if [[ -d "$out_dir/head-tree/.git" || -f "$out_dir/head-tree/.git" ]]; then
  git worktree remove --force "$out_dir/head-tree"
elif [[ -e "$out_dir/head-tree" ]]; then
  echo "Refusing to overwrite non-worktree path: $out_dir/head-tree" >&2
  exit 1
fi

git worktree add --detach "$out_dir/head-tree" "$head_sha" >/dev/null

printf 'Review bundle created at %s\n' "$out_dir"
printf 'Base: %s\nHead: %s\nMerge-base: %s\n' "$base_sha" "$head_sha" "$merge_base"
