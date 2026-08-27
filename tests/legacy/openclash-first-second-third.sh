#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
bash "$ROOT/tests/openclash-xhttp-filter.sh" >/dev/null
grep -q 'generated_index' "$PKG/root/usr/bin/cf-ip-auto-legacy"
echo 'OpenClash first/second/third rerun passed'
