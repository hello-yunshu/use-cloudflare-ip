#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"
cfip_restart_service() { : >"$TMP/restarted"; }
CFIP_TXN_ORIGINAL_RUNNING=false; cfip_txn_restart_original_service passwall recovery; test ! -e "$TMP/restarted"
CFIP_TXN_ORIGINAL_RUNNING=true; cfip_txn_restart_original_service passwall recovery; test -e "$TMP/restarted"
echo 'original service-state preservation contract passed'
