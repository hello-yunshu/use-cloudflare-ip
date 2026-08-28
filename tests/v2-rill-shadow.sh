#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFIP_RUN_ID=shadow-test; CFIP_LOG_FILE="$TMP/log"; CFIP_RILL_ENABLED=true; CFIP_RILL_MODE=shadow; CFIP_RILL_RUNTIME="$TMP/fake-runtime"; CFIP_RILL_STATE="$TMP/state.json"; CFIP_RILL_TIMEOUT_S=2
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat >"$TMP/native.json" <<'JSON'
[{"ip":"104.16.1.1","nativeRank":1},{"ip":"104.16.1.2","nativeRank":2}]
JSON
cat >"$TMP/fake-runtime" <<'EOF_A'
#!/bin/sh
read -r request
method=$(printf '%s' "$request" | jq -r '.request.method')
case "$method" in
 handshake) echo '{"apiVersion":3,"runtimeIdentity":{"name":"rill-runtime","version":"1.5.5"},"stateGeneration":0,"response":{"kind":"handshake","capabilities":["org.rill.preview.decide"],"featureSchemaHash":"abababababababababababababababababababababababababababababababab","handlerApiVersion":2}}' ;;
 decide) echo '{"requestId":"decision-shadow-test","apiVersion":3,"stateGeneration":1,"response":{"kind":"result","output":{"accepted":true,"selectedAction":1}}}' ;;
 feedback) echo '{"requestId":"feedback-shadow-test","apiVersion":3,"stateGeneration":2,"response":{"kind":"result","output":{"accepted":true}}}' ;;
esac
EOF_A
chmod +x "$TMP/fake-runtime"
cfip_rill_rank_shadow "$TMP/native.json" "$TMP/rill.json"
test "$(jq -r '.candidates[0].ip' "$TMP/rill.json")" = 104.16.1.2
# Shadow output may disagree, but host selection remains Native-owned outside this function.
jq -e '.generation==1' "$TMP/rill.json" >/dev/null
echo 'v2 Rill shadow boundary test passed'
