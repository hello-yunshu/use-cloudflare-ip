#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFIP_RUNTIME_DIR="$TMP/runtime"; CFIP_STATUS_DIR="$TMP/status"; CFIP_LOG_FILE="$TMP/log"; mkdir -p "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh"
cat >"$TMP/fake-init" <<'INIT'
#!/bin/sh
exit 0
INIT
chmod +x "$TMP/fake-init"
CFIP_PUBLISH_INIT="$TMP/fake-init"; CFIP_PUBLISH_DIR="$TMP/publish"; CFIP_PUBLISH_STATUS_FILE="$TMP/publisher.json"; CFIP_PUBLISH_ENABLED=true; CFIP_PUBLISH_BIND=192.168.1.1; CFIP_PUBLISH_PORT=12345; CFIP_RUN_ID=test-run
cat >"$TMP/selected.json" <<'JSON'
[{"ip":"104.16.1.1","family":"ipv4"},{"ip":"2606:4700::1","family":"ipv6"}]
JSON
cfip_publish_result "$TMP/selected.json"
grep -qx '104.16.1.1' "$TMP/publish/best-ipv4.txt"
grep -qx '2606:4700::1' "$TMP/publish/best-ipv6.txt"
test "$(wc -l <"$TMP/publish/ip.txt")" -eq 2
jq -e '.success==true and .count==2 and .port==12345' "$TMP/publisher.json" >/dev/null
echo 'v2 LAN publisher test passed'
