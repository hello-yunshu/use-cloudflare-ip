#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
grep -q 'ownership' "$PKG/root/usr/libexec/cf-ip/transaction.sh"
grep -q 'target_domain' "$ROOT/plans/transaction/PASSWALL-OWNERSHIP.md"
echo 'PassWall target removal policy passed'
