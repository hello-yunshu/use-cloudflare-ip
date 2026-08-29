#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '#!/usr/bin/env bash\nsleep 4\n' >"$TMP/runtime"; chmod +x "$TMP/runtime"
printf '{"schema":"cloudflare-ip.rill.v1","version":1}\n' >"$TMP/schema.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
start=$(date +%s)
export CFIP_RUN_ID=status-timeout CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_RILL_RUNTIME="$TMP/runtime" CFIP_RILL_SCHEMA_FILE="$TMP/schema.json" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_TIMEOUT_S=1 CFIP_LOG_FILE="$TMP/log"
cfip_rill_status_json >"$TMP/status.json"
elapsed=$(( $(date +%s)-start )); test "$elapsed" -lt 4
jq -e '.available==false and (.state=="incompatible" or .state=="schema-unavailable")' "$TMP/status.json" >/dev/null
echo 'Rill status timeout fallback contract passed'
