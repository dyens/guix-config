#!/usr/bin/env bash
# Записать ревью в refs/notes/review на указанный коммит и опубликовать.
# Usage: save-review-note.sh <sha> <review-markdown-file>
set -euo pipefail

NOTES_REF=review
TMP_REF="refs/notes/${NOTES_REF}-remote"

sha=${1:?usage: save-review-note.sh <sha> <review-file>}
body=${2:?usage: save-review-note.sh <sha> <review-file>}

full_sha=$(git rev-parse --verify "${sha}^{commit}")
[[ -s "$body" ]] || { echo "review file is empty: $body" >&2; exit 1; }

# 1. Подтянуть remote-состояние notes в отдельный ref и слить, не затирая локальное.
git fetch -f origin "refs/notes/${NOTES_REF}:${TMP_REF}" 2>/dev/null || true
if git rev-parse --verify --quiet "$TMP_REF" >/dev/null; then
  if git rev-parse --verify --quiet "refs/notes/${NOTES_REF}" >/dev/null; then
    git notes --ref="$NOTES_REF" merge -s cat_sort_uniq "$TMP_REF" >/dev/null
  else
    git update-ref "refs/notes/${NOTES_REF}" "$TMP_REF"
  fi
fi

# 2. Номер раунда — по уже лежащим заголовкам в заметке.
round=1
if existing=$(git notes --ref="$NOTES_REF" show "$full_sha" 2>/dev/null); then
  round=$(( $(printf '%s\n' "$existing" | grep -c '^### Review round' || true) + 1 ))
fi

staged=$(mktemp)
trap 'rm -f "$staged"' EXIT
{
  printf '### Review round %s — %s — reviewed %s\n\n' \
    "$round" "$(date -I)" "$(git rev-parse --short "$full_sha")"
  cat "$body"
  printf '\n'
} >"$staged"

# 3. append, не add -f: прошлые раунды остаются.
git notes --ref="$NOTES_REF" append -F "$staged" "$full_sha"
git push origin "refs/notes/${NOTES_REF}"
git update-ref -d "$TMP_REF" 2>/dev/null || true

cat <<EOF

=== saved: round ${round} on ${full_sha} (refs/notes/${NOTES_REF}) ===
Передай автору:

# один раз на клон: чтобы обычный git fetch приносил ревью
git config --add remote.origin.fetch '+refs/notes/*:refs/notes/*'

# прочитать ревью
git fetch origin
git log --notes=${NOTES_REF} -1 ${full_sha}

# если уже сделан rebase/force-push — коммит больше не достижим из ветки,
# команда выше покажет пусто, хотя заметка цела. Тогда:
git fetch origin
git notes --ref=${NOTES_REF} list | grep ${full_sha} | cut -d' ' -f1 | xargs git cat-file -p
EOF
