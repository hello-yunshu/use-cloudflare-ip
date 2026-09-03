#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
INIT="$PKG/root/etc/init.d/cf_ip"
for fn in start_service stop_service reload_service service_triggers validate_cf_ip; do grep -q "^$fn" "$INIT" || fail "missing init lifecycle $fn"; done
grep -q 'cf-ip-auto --run' "$INIT"; grep -q 'cf-ip-auto --download-cfst' "$INIT"; grep -q -- '--sync' "$INIT"
echo 'legacy service lifecycle contract passed'
