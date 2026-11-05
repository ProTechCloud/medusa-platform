#!/usr/bin/env bash
set -euo pipefail
if [ "$EVENT_NAME" = "pull_request" ]; then
  gitleaks git --redact --verbose \
    --log-opts="$BASE_SHA..$HEAD_SHA"
else
  gitleaks git --redact --verbose
fi
