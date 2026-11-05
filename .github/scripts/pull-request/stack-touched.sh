#!/usr/bin/env bash
# A plan that is skipped reports as passed to branch protection, so the job
# always runs and decides here whether there is work. Outside a pull request
# there always is.
set -euo pipefail
if [ "$EVENT_NAME" != "pull_request" ]; then
  echo "relevant=true" >> "$GITHUB_OUTPUT"
  exit 0
fi
changed=$(git diff --name-only "$BASE_SHA" "$HEAD_SHA")
if grep -qE "$PATTERN" <<< "$changed"; then
  echo "relevant=true" >> "$GITHUB_OUTPUT"
else
  echo "relevant=false" >> "$GITHUB_OUTPUT"
  echo "no change matches $PATTERN"
fi
