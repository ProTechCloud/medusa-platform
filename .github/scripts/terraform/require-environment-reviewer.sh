#!/usr/bin/env bash
# The bootstrap admin holds owner on the management project, and the required
# reviewer is what stands between a merge and an apply as that identity. A rule
# existing proves nothing about this run, so this also refuses an environment an
# administrator can bypass, and a run nobody approved.
set -euo pipefail
settings=$(gh api "repos/$REPO/environments/$ENVIRONMENT")

bars_self_review=$(jq '[.protection_rules[]? | select(.type == "required_reviewers" and .prevent_self_review == true)] | length' <<< "$settings")
if [ "$bars_self_review" -eq 0 ]; then
  echo "::error::$ENVIRONMENT must have a required reviewer rule that bars self-review. Nothing was applied."
  exit 1
fi

if [ "$(jq -r '.can_admins_bypass' <<< "$settings")" != "false" ]; then
  echo "::error::$ENVIRONMENT must not let administrators bypass its rules. Nothing was applied."
  exit 1
fi

approved=$(gh api "repos/$REPO/actions/runs/$GITHUB_RUN_ID/approvals" --jq \
  "[.[] | select(.state == \"approved\" and any(.environments[]; .name == \"$ENVIRONMENT\"))] | length")
if [ "$approved" -eq 0 ]; then
  echo "::error::No reviewer approved this run in $ENVIRONMENT. Nothing was applied."
  exit 1
fi
