#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
grep -q 'openclash.yaml' "$PKG/root/usr/libexec/cf-ip/transaction.sh"
grep -q 'cfip_txn_rollback' "$PKG/root/usr/libexec/cf-ip/transaction.sh"
echo 'OpenClash rollback contract passed'
