#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/runtime" <<'EOF'
#!/usr/bin/env bash
: >"${RILL_MARKER:?}"
EOF
chmod +x "$TMP/runtime"
printf '{"schema":"cloudflare-ip.rill.v1","version":1}\n' >"$TMP/schema.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
export CFIP_RILL_ENABLED=false CFIP_RILL_MODE=shadow CFIP_RILL_RUNTIME="$TMP/runtime" CFIP_RILL_SCHEMA_FILE="$TMP/schema.json" CFIP_RILL_STATE="$TMP/state.json" CFIP_LOG_FILE="$TMP/log" RILL_MARKER="$TMP/marker"
cfip_rill_status_json >"$TMP/status.json"
test ! -e "$TMP/marker"
jq -e '.state=="disabled" and .available==false' "$TMP/status.json" >/dev/null
echo 'Rill disabled no-exec contract passed'
