#!/usr/bin/env bash
set -euo pipefail
tunnel=$(curl -sS -H "Authorization: Bearer $CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel?name=medusa-stg&is_deleted=false" \
  | jq -r '.result[0].id // empty')

if [ -z "$tunnel" ]; then
  echo "::error::No tunnel named medusa-stg. Apply terraform/live/stg/cloudflare first."
  exit 1
fi

# `// empty` and the guard below, for the same reason as the tunnel
# lookup above: on a failed call `.result` is null, `jq -r` prints
# the string "null", and that would be written as the latest version
# of the secret. The VM reads versions/latest at boot, so cloudflared
# would then fail with a token error and nothing would point at the
# API call that caused it. Masking "null" also hides every later null
# in the log.
value=$(curl -sS -H "Authorization: Bearer $CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$tunnel/token" \
  | jq -r 'if .success then (.result // empty) else empty end')

if [ -z "$value" ]; then
  echo "::error::Cloudflare did not return a tunnel token for medusa-stg. The secret was left untouched."
  exit 1
fi
echo "::add-mask::$value"

# Through stdin, never an argument: arguments show up in process
# listings and in gcloud's own command log.
printf '%s' "$value" | gcloud secrets versions add "$SECRET" \
  --project="$PROJECT" \
  --impersonate-service-account="$WRITER" \
  --data-file=-
