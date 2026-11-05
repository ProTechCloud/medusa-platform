#!/usr/bin/env bash
set -euo pipefail
echo "$RESULTS"
failed=$(echo "$RESULTS" | jq -r '
  to_entries[]
  | select(.value.result != "success" and .value.result != "skipped")
  | .key')
if [ -n "$failed" ]; then
  echo "::error::failed or timed out: $(echo "$failed" | tr '\n' ' ')"
  exit 1
fi
echo "all checks passed"
