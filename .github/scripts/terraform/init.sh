#!/usr/bin/env bash
# -lockfile=readonly: init fails rather than silently adding a provider hash, so
# a dependency cannot change under a reviewed plan. SPOKE is unset for a root
# that signs in as itself.
set -euo pipefail
terraform init -lockfile=readonly \
  -backend-config="bucket=$BUCKET" \
  ${SPOKE:+-backend-config="impersonate_service_account=$SPOKE"}
