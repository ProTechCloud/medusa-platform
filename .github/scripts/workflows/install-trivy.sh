#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
tarball="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
curl -sSfLO "$base/$tarball"
curl -sSfL "$base/trivy_${TRIVY_VERSION}_checksums.txt" \
  | grep " $tarball\$" | sha256sum -c -
tar -xzf "$tarball" trivy
sudo mv trivy /usr/local/bin/
