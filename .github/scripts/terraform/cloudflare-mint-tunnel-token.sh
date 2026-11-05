#!/usr/bin/env bash
set -euo pipefail
groups=$(curl -sS -H "Authorization: Bearer $MINT_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tokens/permission_groups")
# Stop on Cloudflare's own error, not on what it leaves behind. A
# refused call has no .result, so without this every lookup below
# fails with "Cannot iterate over null" and the reason only shows
# after the token request, at the bottom of the log.
if [ "$(echo "$groups" | jq -r '.success')" != "true" ]; then
  echo "::error::Cloudflare refused CLOUDFLARE_MINT_TOKEN. It must be an account token" \
    "with Account API Tokens Write, made under Manage Account → API Tokens;" \
    "a user token from My Profile is refused here."
  echo "$groups" | jq '.errors'
  exit 1
fi
tunnel_write=$(echo "$groups" | jq -r '.result[] | select(.name=="Cloudflare Tunnel Write") | .id' | head -1)
[ -n "$tunnel_write" ] || { echo "::error::no Cloudflare Tunnel Write permission group"; exit 1; }

body=$(jq -n \
  --arg name "medusa-tunnel-token-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" \
  --arg acct "$ACCOUNT_ID" --arg g "$tunnel_write" \
  '{name: $name, policies: [{effect: "allow",
    resources: {("com.cloudflare.api.account." + $acct): "*"},
    permission_groups: [{id: $g}]}]}')

created=$(curl -sS -X POST -H "Authorization: Bearer $MINT_TOKEN" \
  -H "Content-Type: application/json" -d "$body" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tokens")
[ "$(echo "$created" | jq -r '.success')" = "true" ] || { echo "::error::mint failed"; exit 1; }

token=$(echo "$created" | jq -r '.result.value')
echo "::add-mask::$token"
echo "CF_TOKEN=$token" >> "$GITHUB_ENV"
echo "token_id=$(echo "$created" | jq -r '.result.id')" >> "$GITHUB_OUTPUT"
