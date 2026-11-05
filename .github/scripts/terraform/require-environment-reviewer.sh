#!/usr/bin/env bash
# The bootstrap admin holds owner on the management project, and the required
# reviewer is what stands between a merge and an apply as that identity. An
# environment whose rule was removed would apply unreviewed, so this refuses.
set -euo pipefail
bars_self_review=$(gh api "repos/$REPO/environments/$ENVIRONMENT" \
  --jq '[.protection_rules[]? | select(.type == "required_reviewers" and .prevent_self_review == true)] | length')
if [ "$bars_self_review" -eq 0 ]; then
  echo "::error::$ENVIRONMENT must have a required reviewer rule that bars self-review. Nothing was applied."
  exit 1
fi
