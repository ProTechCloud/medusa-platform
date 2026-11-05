#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}"
tarball="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
curl -sSfLO "$base/$tarball"
curl -sSfL "$base/gitleaks_${GITLEAKS_VERSION}_checksums.txt" \
  | grep " $tarball\$" | sha256sum -c -
tar -xzf "$tarball" gitleaks
sudo mv gitleaks /usr/local/bin/
