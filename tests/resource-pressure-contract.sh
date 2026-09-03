#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_LOG_FILE="$TMP/log" CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_ENABLED=true CFIP_RILL_MODE=assisted CFIP_RUN_ID=resource-pressure
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_RILL_RUNTIME="$TMP/fake-runtime"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat > "$CFIP_RILL_RUNTIME" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
request="$(cat)"; method="$(jq -r '.request.method // empty' <<<"$request")"; id="$(jq -r '.requestId' <<<"$request")"; schema="$(jq -r '.featureSchemaHash' <<<"$request")"
case "$method" in
  handshake) jq -cn --arg id "$id" --arg schema "$schema" '{requestId:$id,apiVersion:3,modelGeneration:2,stateGeneration:4,runtimeIdentity:{name:"rill-runtime",version:"0.2.0-preview"},response:{kind:"handshake",channel:"preview",featureSchemaHash:$schema,handlerApiVersion:2,capabilities:["org.rill.preview.decide","org.rill.preview.feedback","org.rill.preview.inspect"]}}' ;;
  health) jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"health",healthy:true,status:"healthy",reasonCodes:[]}}' ;;
  inspect) jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"inspection",summary:{resourceProfile:{maxModelStateBytes:100,maxPendingDecisions:100,maxCompletedDecisions:100},resourceUtilization:{stateBytes:95,pendingDecisions:1,completedDecisions:1},pendingDecisions:1,completedDecisions:1}}}' ;;
  *) exit 2 ;;
esac
SH
chmod +x "$CFIP_RILL_RUNTIME"
status="$(cfip_rill_status_json)"
test "$(jq -r '.resourcePressure' <<<"$status")" = true
test "$(jq -r '.health' <<<"$status")" = resource_pressure
test "$(jq -r '.healthHealthy' <<<"$status")" = false
test "$(jq -r '.healthReasonCodes|index("resource_pressure") != null' <<<"$status")" = true
if cfip_rill_assisted_ready; then exit 1; fi
echo 'Runtime inspect resource-pressure contract passed'
