#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '100.0 0.0\n' >"$TMP/uptime"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
export CFIP_MONOTONIC_FILE="$TMP/uptime" CFIP_MEASUREMENT_DEADLINE=110 CFIP_RECOVERY_DEADLINE=120
test "$(cfip_measurement_remaining)" -eq 10
test "$(cfip_recovery_remaining)" -eq 20
# Simulate an NTP wall-clock jump: only the monotonic source changes budgets.
printf '101.0 3600.0\n' >"$TMP/uptime"
test "$(cfip_measurement_remaining)" -eq 9
test "$(cfip_recovery_remaining)" -eq 19
echo 'monotonic deadline contract passed'
