#!/usr/bin/env bash
# The comment cuts a long plan, so each stack keeps its full plan.txt here, with a
# run.txt naming what produced it. Under a random id: the identity may only create
# objects, so a re-run cannot replace a plan someone is reading. Through the JSON
# API because gcloud storage also lists and reads, which this identity cannot do.
# SPOKE is set when the job signs in as a hub, which holds nothing and has to
# become its spoke first.
#
# The caller turns a failure here into a warning: a plan is never red because of
# the store.
set -euo pipefail
if [ -z "${BUCKET:-}" ]; then
  echo "no plan store is set: skipping the upload"
  exit 0
fi

prefix="plan/$STACK/$(openssl rand -hex 16)/"
token=$(gcloud auth print-access-token ${SPOKE:+--impersonate-service-account="$SPOKE"})
echo "::add-mask::$token"

upload() {
  name=$(jq -rn --arg object "$prefix$2" '$object | @uri')
  curl -sSf -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: text/plain" \
    --data-binary @"$1" \
    "https://storage.googleapis.com/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=$name" > /dev/null
}

printf 'ref: %s\nrun: %s\ncommit: %s\n' "$GITHUB_REF" "$GITHUB_RUN_ID" "$GITHUB_SHA" > run.txt
upload plan.txt plan.txt
upload run.txt run.txt
# Beside the summary, so the comment builds the link from it.
echo "$prefix" > plan-prefix.txt
