#!/usr/bin/env bash
# pipefail is load-bearing: without it the step reports tee's exit status, and a
# plan that errored shows as a green check.
set -euo pipefail
terraform plan -no-color -input=false -lock=false -out=tfplan 2>&1 | tee plan.txt
