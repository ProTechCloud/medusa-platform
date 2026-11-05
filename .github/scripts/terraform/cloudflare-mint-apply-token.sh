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
# A name that matches nothing would leave an empty id in the policy,
# and Cloudflare's answer to that names neither the group nor the
# field. Failing here names the group.
id_of() {
  id=$(echo "$groups" | jq -r --arg n "$1" '.result[] | select(.name==$n) | .id' | head -1)
  [ -n "$id" ] || { echo "::error::No Cloudflare permission group named \"$1\"" >&2; return 1; }
  echo "$id"
}
tunnel_write=$(id_of 'Cloudflare Tunnel Write')
zone_read=$(id_of 'Zone Read')
dns_write=$(id_of 'DNS Write')
settings_write=$(id_of 'Zone Settings Write')

body=$(jq -n \
  --arg name "medusa-apply-$STACK-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" \
  --arg expires "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" \
  --arg acct "$ACCOUNT_ID" --arg zone "$ZONE_ID" \
  --arg tunnel_write "$tunnel_write" \
  --arg zone_read "$zone_read" \
  --arg dns_write "$dns_write" \
  --arg settings_write "$settings_write" \
  '{name: $name,
    expires_on: $expires,
    policies: [
      {effect: "allow",
       resources: {("com.cloudflare.api.account." + $acct): "*"},
       permission_groups: [{id: $tunnel_write}]},
      {effect: "allow",
       resources: {("com.cloudflare.api.account.zone." + $zone): "*"},
       permission_groups: [{id: $zone_read}, {id: $dns_write}, {id: $settings_write}]}
    ]}')

created=$(curl -sS -X POST -H "Authorization: Bearer $MINT_TOKEN" \
  -H "Content-Type: application/json" -d "$body" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tokens")

if [ "$(echo "$created" | jq -r '.success')" != "true" ]; then
  echo "::error::Could not mint a Cloudflare token"
  echo "$created" | jq -r '.errors'
  exit 1
fi

token=$(echo "$created" | jq -r '.result.value')
echo "::add-mask::$token"
echo "CLOUDFLARE_API_TOKEN=$token" >> "$GITHUB_ENV"
echo "token_id=$(echo "$created" | jq -r '.result.id')" >> "$GITHUB_OUTPUT"
