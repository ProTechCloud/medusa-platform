#!/usr/bin/env bash
set -euo pipefail
trivy config terraform/ \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --ignorefile .trivyignore.yaml
