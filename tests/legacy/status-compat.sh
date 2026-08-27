#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
grep -q 'running:\$enabled' "$PKG/root/usr/bin/cf-ip-auto-v2"
grep -q 'active_run:\$activeRun' "$PKG/root/usr/bin/cf-ip-auto-v2"
grep -q 'env:{tar:' "$PKG/root/usr/bin/cf-ip-auto-v2"
echo 'legacy status compatibility contract passed'
