#!/usr/bin/env bash
set -euo pipefail
stale=$(gh run list --repo "$REPO" --workflow=code-quality.yml \
          --branch "$BRANCH" --json databaseId,status \
          --jq ".[] | select((.status==\"in_progress\" or .status==\"queued\") and (.databaseId | tostring) != \"${THIS_RUN}\") | .databaseId")
[ -z "$stale" ] && { echo "nothing to cancel"; exit 0; }

# A completed run can race with cancellation. Every other failed request must
# be visible, including a failed status lookup: it does not mean the run is gone.
cancel_run() {
  local id=$1 operation=$2 error state
  if [ "$operation" = force-cancel ]; then
    if error=$(gh api -X POST "repos/$REPO/actions/runs/$id/force-cancel" 2>&1); then
      return 0
    fi
  else
    if error=$(gh run cancel "$id" --repo "$REPO" 2>&1); then
      return 0
    fi
  fi
  if state=$(gh run view "$id" --repo "$REPO" --json status --jq .status) && [ "$state" = completed ]; then
    echo "$id already completed"
  else
    echo "::warning::$operation failed for run $id: $error"
  fi
}

for id in $stale; do
  echo "cancelling $id"
  cancel_run "$id" cancel
done

# Each run gets until the deadline to stop by itself, and only what is still alive
# after that is forced.
deadline=$((SECONDS + 20))
for id in $stale; do
  while :; do
    if ! state=$(gh run view "$id" --repo "$REPO" --json status --jq .status); then
      echo "::warning::Could not read status for run $id; attempting force-cancel."
      break
    fi
    if [ "$state" != "in_progress" ] && [ "$state" != "queued" ]; then
      continue 2
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      break
    fi
    sleep 3
  done
  echo "still alive, forcing $id"
  cancel_run "$id" force-cancel
done
