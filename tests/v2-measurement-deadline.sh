#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_LOG_FILE="$TMP/log" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
CFIP_MEASUREMENT_DEADLINE=$(( $(date +%s) + 1 )); test "$(cfip_deadline_remaining)" -le 1
CFIP_MEASUREMENT_DEADLINE=$(( $(date +%s) - 1 )); test "$(cfip_deadline_remaining)" -eq 0
set +e; cfip_run_with_timeout 1 bash -c 'sleep 2'; rc=$?; set -e; test "$rc" -eq 124
grep -q 'CFIP_MEASUREMENT_DEADLINE' "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
grep -q 'measurement_timeout' "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
echo 'v2 global measurement deadline contract passed'
