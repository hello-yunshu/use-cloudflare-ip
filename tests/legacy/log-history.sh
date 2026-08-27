#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
grep -q 'tail -n 500' "$PKG/root/usr/libexec/cf-ip/common.sh"
grep -q 'tail -n 100' "$PKG/root/usr/bin/cf-ip-auto-v2"
echo 'legacy bounded log/history contract passed'
