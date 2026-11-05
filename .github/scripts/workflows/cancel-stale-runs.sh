#!/usr/bin/env bash
set -euo pipefail
stale=$(gh run list --repo "$REPO" --workflow=code-quality.yml \
          --branch "$BRANCH" --json databaseId,status \
          --jq '.[] | select(.status=="in_progress" or .status=="queued") | .databaseId' \
        | grep -v "^${THIS_RUN}$" || true)
[ -z "$stale" ] && { echo "nothing to cancel"; exit 0; }

for id in $stale; do
  echo "cancelling $id"
  gh run cancel "$id" --repo "$REPO" || true
done

sleep 20

for id in $stale; do
  state=$(gh run view "$id" --repo "$REPO" --json status --jq .status 2>/dev/null || echo gone)
  if [ "$state" = "in_progress" ] || [ "$state" = "queued" ]; then
    echo "still alive, forcing $id"
    gh api -X POST "repos/$REPO/actions/runs/$id/force-cancel" || true
  fi
done
