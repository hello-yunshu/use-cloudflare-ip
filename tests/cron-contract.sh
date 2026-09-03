#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V2="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
LIB="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
run_cron() { CFIP_LIB_DIR="$LIB" CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log" bash "$V2" --to-cron "$@"; }
test "$(run_cron 6h '')" = '0 */6 * * *'
test "$(run_cron 15m '')" = '*/15 * * * *'
test "$(run_cron 30m '')" = '*/30 * * * *'
test "$(run_cron 1h '')" = '0 * * * *'
test "$(run_cron '0 3 * * *' '')" = '0 3 * * *'
test "$(run_cron '0 3,15 * * *' '')" = '0 3,15 * * *'
test "$(run_cron '0 */6 * * *' '')" = '0 */6 * * *'
test "$(run_cron custom 30m)" = '*/30 * * * *'
test "$(run_cron custom '0 3,15 * * *')" = '0 3,15 * * *'
if run_cron custom $'0 3 * * *\n/etc/passwd' >/dev/null 2>&1; then exit 1; fi
if run_cron custom '0 3 * * *;id' >/dev/null 2>&1; then exit 1; fi
grep -Fq 'cf-ip-auto --to-cron "$cron_interval" "$cron_custom"' "$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip"
echo 'cron/init/CLI roundtrip contract passed'
