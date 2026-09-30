#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: prepare-review-lanes.sh <bundle-dir>

Splits an existing prepare-review-bundle.sh output into topic lanes.
Creates lanes/<lane>/{files.txt,diff.patch,diff-u80.patch,brief.md}.
USAGE
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

bundle_dir=${1%/}
metadata=$bundle_dir/metadata.txt
files=$bundle_dir/files.txt

if [[ ! -f "$metadata" || ! -f "$files" ]]; then
  echo "Bundle must contain metadata.txt and files.txt: $bundle_dir" >&2
  exit 1
fi

base_sha=$(grep '^base_sha=' "$metadata" | cut -d= -f2-)
head_sha=$(grep '^head_sha=' "$metadata" | cut -d= -f2-)
lanes_dir=$bundle_dir/lanes
mkdir -p "$lanes_dir"

lane() {
  local name=$1
  local pattern=$2
  local brief=$3
  local dir=$lanes_dir/$name
  mkdir -p "$dir"
  grep -E "$pattern" "$files" > "$dir/files.txt" || true
  cat > "$dir/brief.md" <<EOF
# Lane: $name

$brief

Authoritative range: $base_sha...$head_sha
Read files.txt first. Review only these paths unless following an end-to-end contract requires a directly related path from the main bundle.
EOF
  if [[ -s "$dir/files.txt" ]]; then
    git diff --find-renames --find-copies "$base_sha...$head_sha" -- $(cat "$dir/files.txt") > "$dir/diff.patch"
    git diff --find-renames --find-copies --unified=80 "$base_sha...$head_sha" -- $(cat "$dir/files.txt") > "$dir/diff-u80.patch"
  else
    : > "$dir/diff.patch"
    : > "$dir/diff-u80.patch"
  fi
}

lane tenant-theme '(^internal/(http/tenants|userapi|core/.*/settings|infra/pg/settings|app/settings|gateway/methods/config)|^api/user|^ui/(web|user-front)/src/(api|theme|components/providers|hooks/use-session-identity|auth/authenticated-boundary|pages/tenant-profile)|^docs/settings-registry)' \
  'End-to-end tenant theme/settings contract: registry, storage/API, generated contract, frontend application, tenant switch/logout/stale data tests.'

lane design-contrast '(^ui/design-system|theme\.generated\.css$|theme-(runtime|contract|dom|bootstrap)|samurai\.css$|workspace\.css$|index\.css$|tenant-theme-contrast|brand/|public/(brand|theme-bootstrap|favicon|manifest))' \
  'Design tokens, generated CSS, runtime variables, WCAG contrast, dark/light defaults, brand assets/bootstrap delivery.'

lane accessibility-components '(^ui/(web|user-front)/src/(components/ui|components/layout|shared/ui|features/chat|pages/.+\.tsx)|select|dialog|composer|results-panel|file-preview|action-history)' \
  'Interactive frontend components: keyboard navigation, focus visibility, ARIA, visible state, dialogs, chat/file action UX.'

lane go-settings-api '(^internal/(core|infra|gateway|http|app|agent|channels|userapi)|^cmd/|^pkg/|^migrations/|^api/)' \
  'Go backend correctness: settings registry, tenant scoping, API compatibility, authz, generated OpenAPI/Go-first contract, tests.'

lane generated-parity '(^api/|openapi|gen/|generated|\.generated\.|pnpm-lock\.yaml$|pnpm-workspace\.yaml$|package\.json$|settings-registry\.md$|ui_theme_parity|go_first_schema|contract)' \
  'Generated artifacts and parity checks: lockfiles, OpenAPI, generated clients/schemas, docs generated from registry, fragile tests.'

lane ops-readiness '(^\.gitlab-ci\.yml$|^scripts/ci/|^deploy/|^docker-compose|^docs/superpowers/debt\.md$|rollback|bundle-budget|production-preview|gitleaks)' \
  'CI/release readiness: pipeline coverage, bundle budgets, rollback/provenance notes, security allowlists, operational docs.'

printf 'Review lanes created under %s\n' "$lanes_dir"
find "$lanes_dir" -maxdepth 2 -name files.txt -print | sort | while read -r f; do
  printf '%s: %s files\n' "$(basename "$(dirname "$f")")" "$(wc -l < "$f")"
done
