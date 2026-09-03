#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
grep -q 'tar_ok' "$PKG/root/usr/bin/cf-ip-auto-v2"
grep -q 'passwall_installed' "$PKG/root/usr/bin/cf-ip-auto-v2"
grep -q 'openclash_running' "$PKG/root/usr/bin/cf-ip-auto-v2"
echo 'legacy environment contract passed'
