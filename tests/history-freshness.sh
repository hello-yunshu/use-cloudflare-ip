#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
now=$(date +%s)
printf '{"result":"success","time":%s,"bestIps":["104.16.1.1"]}\n{"result":"success","time":%s,"bestIps":["104.16.1.2"]}\n' "$((now-7200))" "$((now-60))" >"$TMP/history.ndjson"
CFIP_RUN_HISTORY="$TMP/history.ndjson" CFIP_HISTORY_MAX_AGE_SECONDS=3600 cfip_history_pool_json "$TMP/pool.json"
test "$(jq length "$TMP/pool.json")" -eq 1; test "$(jq -r '.[0].ip' "$TMP/pool.json")" = 104.16.1.2
echo 'history freshness contract passed'
