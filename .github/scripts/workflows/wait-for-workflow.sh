#!/usr/bin/env bash
# Waits for WORKFLOW's run on this commit when the push touched PATHS, one path
# prefix per line, and fails unless that run succeeded. The approval it may be
# waiting on has no deadline of its own, so the caller's timeout-minutes is the
# limit.
set -euo pipefail
if [ "$EVENT_NAME" != "push" ]; then
  echo "not a push: nothing to wait for"
  exit 0
fi

touched=false
changed=$(git diff --name-only "$BEFORE_SHA" "$GITHUB_SHA")
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if grep -q "^$path" <<< "$changed"; then
    touched=true
  fi
done <<< "$PATHS"
if [ "$touched" = false ]; then
  echo "this push touched none of the paths: nothing to wait for"
  exit 0
fi

# The other workflow starts from the same push, so its run may not exist yet.
deadline=$((SECONDS + 300))
while :; do
  run=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --commit "$GITHUB_SHA" --event push \
    --limit 1 --json status,conclusion,url --jq '.[0] // empty')
  if [ -n "$run" ] && [ "$(echo "$run" | jq -r .status)" = "completed" ]; then
    break
  fi
  if [ -z "$run" ] && [ "$SECONDS" -ge "$deadline" ]; then
    echo "::error::$WORKFLOW has no run on $GITHUB_SHA after five minutes."
    exit 1
  fi
  echo "waiting for $WORKFLOW on $GITHUB_SHA"
  sleep 30
done

conclusion=$(echo "$run" | jq -r .conclusion)
# A newer commit does not make this dependency successful. An older workload
# may still be running, so cancellation must block its apply too.
if [ "$conclusion" != "success" ]; then
  echo "::error::$WORKFLOW ended as $conclusion: $(echo "$run" | jq -r .url)"
  exit 1
fi
echo "$WORKFLOW succeeded"
