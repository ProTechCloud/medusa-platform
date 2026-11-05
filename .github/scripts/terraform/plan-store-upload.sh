#!/usr/bin/env bash
# The comment cuts a long plan, so each stack links its full plan.txt here. Under
# a random prefix: the identity may only create objects, so a re-run cannot
# replace a plan someone is reading. Through the JSON API because gcloud storage
# also lists and reads, which this identity cannot do.
set -euo pipefail
object="${PREFIX}$(openssl rand -hex 16)/plan.txt"
token=$(gcloud auth print-access-token)
echo "::add-mask::$token"
name=$(jq -rn --arg object "$object" '$object | @uri')
curl -sSf -X POST \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: text/plain" \
  --data-binary @plan.txt \
  "https://storage.googleapis.com/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=$name" > /dev/null
echo "https://storage.cloud.google.com/$BUCKET/$object" > plan-url.txt
