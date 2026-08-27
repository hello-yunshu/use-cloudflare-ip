#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
grep -q 'passwall-managed.json.pending' "$PKG/root/usr/libexec/cf-ip/transaction.sh"
grep -q 'rm -f.*passwall-managed.json.pending' "$PKG/root/usr/libexec/cf-ip/transaction.sh"
echo 'PassWall rollback auxiliary-state contract passed'
