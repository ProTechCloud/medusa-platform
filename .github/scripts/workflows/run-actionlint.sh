#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}"
tarball="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
curl -sSfLO "$base/$tarball"
curl -sSfL "$base/actionlint_${ACTIONLINT_VERSION}_checksums.txt" \
  | grep " $tarball\$" | sha256sum -c -
tar -xzf "$tarball" actionlint
./actionlint -color
