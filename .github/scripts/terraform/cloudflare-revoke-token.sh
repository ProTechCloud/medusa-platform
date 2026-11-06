#!/usr/bin/env bash
set -euo pipefail
curl -sS -X DELETE -H "Authorization: Bearer $MINT_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/tokens/$TOKEN_ID" \
  | jq -r '.success' | grep -q true && echo "token revoked"
