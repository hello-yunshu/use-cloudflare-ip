#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
RPC="$PKG/root/usr/libexec/rpcd/cf_ip"
for method in status check-env refresh-env run speedtest-status version read-log clear-log ip-history download-cfst self-update start stop restart sync oc-list-backups oc-restore-backup oc-delete-backup; do grep -q "\"$method\"" "$RPC" || fail "missing RPC $method"; done
grep -q 'CF_IP_AUTO_BIN=' "$RPC"
echo 'legacy overview/RPC surface contract passed'
