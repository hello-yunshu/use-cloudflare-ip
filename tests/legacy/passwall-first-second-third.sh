#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
bash "$ROOT/tests/passwall-managed.sh" >/dev/null
grep -q 'current_address.*saved_address' "$PKG/root/usr/libexec/cf-ip/transaction.sh"
echo 'PassWall first/second/third ownership contract passed'
