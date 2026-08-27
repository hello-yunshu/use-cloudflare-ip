#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFIP_RUN_ID=shadow-test; CFIP_LOG_FILE="$TMP/log"; CFIP_RILL_ENABLED=true; CFIP_RILL_MODE=shadow; CFIP_RILL_STATE="$TMP/state.json"; CFIP_RILL_TIMEOUT_S=2
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat >"$TMP/native.json" <<'JSON'
[{"ip":"104.16.1.1","nativeRank":1},{"ip":"104.16.1.2","nativeRank":2}]
JSON
cat >"$TMP/fake-adapter" <<'EOF_A'
#!/bin/sh
case "$1" in
 status) echo '{"success":true,"rillVersion":"1.5.3","adapterProtocolVersion":1}' ;;
 rank) echo '{"success":true,"rillVersion":"1.5.3","adapterProtocolVersion":1,"generation":7,"candidates":[{"ip":"104.16.1.2","rillRank":1},{"ip":"104.16.1.1","rillRank":2}]}' ;;
 feedback) echo '{"success":true,"accepted":true}' ;;
esac
EOF_A
chmod +x "$TMP/fake-adapter"; CFIP_RILL_ADAPTER="$TMP/fake-adapter"
cfip_rill_rank_shadow "$TMP/native.json" "$TMP/rill.json"
test "$(jq -r '.candidates[0].ip' "$TMP/rill.json")" = 104.16.1.2
# Shadow output may disagree, but host selection remains Native-owned outside this function.
jq -e '.generation==7' "$TMP/rill.json" >/dev/null
echo 'v2 Rill shadow boundary test passed'
