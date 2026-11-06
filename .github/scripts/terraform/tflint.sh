#!/usr/bin/env bash
set -euo pipefail
tflint --init --config="$GITHUB_WORKSPACE/.tflint.hcl"
tflint --config="$GITHUB_WORKSPACE/.tflint.hcl" --minimum-failure-severity=warning
