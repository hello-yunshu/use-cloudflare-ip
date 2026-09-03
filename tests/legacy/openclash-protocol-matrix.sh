#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
bash "$ROOT/tests/openclash-protocol-matrix.sh" >/dev/null
grep -q 'transport_filter' "$PKG/root/usr/bin/cf-ip-auto-legacy"
echo 'OpenClash protocol matrix preservation passed'
