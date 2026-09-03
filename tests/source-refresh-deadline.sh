#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_SOURCE_CACHE_DIR="$TMP/cache" CFIP_LOG_FILE="$TMP/log"
export CFIP_SOURCE_TOTAL_TIMEOUT=2 CFIP_SOURCE_REFRESH_DEADLINE=1 CFIP_SOURCE_MAX_COUNT=16
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
CFIP_SOURCE_REFRESH_DEADLINE=1
test "$(cfip_source_refresh_remaining)" -lt 0
if cfip_source_fetch_remote expired https://example.invalid/list ip-text ipv4 community "$TMP/expired.json"; then exit 1; fi
test "$(jq -r '.lastError' "$CFIP_SOURCE_RUNTIME_DIR/expired/metadata.json")" = source_refresh_deadline
test "$(jq 'length' "$TMP/expired.json")" -eq 0
echo 'Source refresh global deadline contract passed'
