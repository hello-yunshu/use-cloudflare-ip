#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
bash "$ROOT/tests/passwall-managed.sh" >/dev/null
grep -q 'ownership conflict' "$PKG/root/usr/libexec/cf-ip/transaction.sh"
grep -q 'user edit conflict' "$PKG/root/usr/libexec/cf-ip/transaction.sh"
echo 'PassWall conflict contract passed'
