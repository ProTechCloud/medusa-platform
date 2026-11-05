#!/usr/bin/env bash
# Hands a secret to the later steps of this job, masked in their logs.
set -euo pipefail
echo "::add-mask::$VALUE"
echo "$NAME=$VALUE" >> "$GITHUB_ENV"
