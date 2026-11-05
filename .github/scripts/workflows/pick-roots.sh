#!/usr/bin/env bash
set -euo pipefail
all=$(find terraform/live -name versions.tf -exec dirname {} \; | sort)

if [ "$EVENT_NAME" != "pull_request" ]; then
  chosen="$all"
else
  changed=$(git diff --name-only \
    "$BASE_SHA" \
    "$HEAD_SHA")
  if echo "$changed" | grep -q "^terraform/modules/"; then
    chosen="$all"
  else
    chosen=$(for r in $all; do echo "$changed" | grep -q "^$r/" && echo "$r"; done || true)
  fi
fi

# An empty matrix makes the job vanish, and a vanished required check
# reads as passed. One no-op entry keeps the job reporting.
[ -z "$chosen" ] && chosen="none"
echo "roots=$(echo "$chosen" | jq -R . | jq -sc .)" >> "$GITHUB_OUTPUT"
