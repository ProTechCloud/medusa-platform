#!/usr/bin/env bash
set -euo pipefail
# First merge only: the base branch has neither file yet.
root=base
[ -f base/commitlint.config.mjs ] || root=.
dir="$RUNNER_TEMP/commitlint"
mkdir -p "$dir"
cp "$root/commitlint.config.mjs" "$root"/.github/pr-template/package*.json "$dir"
cd "$dir"
npm ci --ignore-scripts --no-audit --no-fund
printf '%s\n' "$TITLE" | ./node_modules/.bin/commitlint --verbose
