#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
bash "$ROOT/tests/legacy/rpc-roundtrip.sh" >/dev/null
grep -q 'oc-list-backups' "$PKG/root/usr/bin/cf-ip-auto-v2"
grep -q 'oc-restore-backup' "$PKG/root/usr/bin/cf-ip-auto-v2"
grep -q 'oc-delete-backup' "$PKG/root/usr/bin/cf-ip-auto-v2"
echo 'OpenClash backup roundtrip passed'
