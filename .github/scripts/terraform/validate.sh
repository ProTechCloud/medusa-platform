#!/usr/bin/env bash
set -euo pipefail
terraform init -backend=false -input=false
terraform validate
