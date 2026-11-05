#!/usr/bin/env bash
set -euo pipefail
value=$(terraform output -raw project_api_token)

# An empty output would become the latest version, and the VM reads
# versions/latest.
if [ -z "$value" ]; then
  echo "::error::terraform output project_api_token is empty. The secret was left untouched."
  exit 1
fi
echo "::add-mask::$value"

deadline=$((SECONDS + 600))
# Through stdin, never an argument: arguments show up in process
# listings and in gcloud's own command log.
until printf '%s' "$value" | gcloud secrets versions add "$SECRET" \
  --project="$PROJECT" \
  --data-file=-; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "::error::$SECRET could not be written for ten minutes. Check that stg-cd created it and its grant."
    exit 1
  fi
  echo "Waiting for $SECRET and its grant from stg-cd…"
  sleep 20
done
