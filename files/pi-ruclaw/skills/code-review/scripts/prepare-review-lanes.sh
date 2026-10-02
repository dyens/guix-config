#!/usr/bin/env bash
set -euo pipefail
# Resolve supporting code relative to this skill, not the caller's checkout.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/review_batches.py" "$@"
