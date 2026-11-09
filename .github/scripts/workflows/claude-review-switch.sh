#!/usr/bin/env bash
set -euo pipefail
case "$STATE" in
  on) action=enable ;;
  off) action=disable ;;
  *) echo "::error::state must be on or off"; exit 1 ;;
esac
gh api -X PUT "repos/$GITHUB_REPOSITORY/actions/workflows/claude-code-review.yml/$action"
gh api "repos/$GITHUB_REPOSITORY/actions/workflows/claude-code-review.yml" \
  --jq '"Claude Code Review is now \(.state)"'
