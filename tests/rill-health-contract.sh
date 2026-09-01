#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CFIP_LOG_FILE="$TMP/log" CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json"
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=assisted CFIP_RUN_ID=health-contract
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
export CFIP_RILL_RUNTIME="$TMP/fake-runtime"

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

cat > "$CFIP_RILL_RUNTIME" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
request="$(cat)"
method="$(jq -r '.request.method // empty' <<<"$request")"
id="$(jq -r '.requestId' <<<"$request")"
schema="$(jq -r '.featureSchemaHash' <<<"$request")"
case "$method" in
  handshake)
    jq -cn --arg id "$id" --arg schema "$schema" '{requestId:$id,apiVersion:3,modelGeneration:2,stateGeneration:9,runtimeIdentity:{name:"rill-runtime",version:"0.2.0-preview"},response:{kind:"handshake",channel:"preview",featureSchemaHash:$schema,handlerApiVersion:2,capabilities:["org.rill.preview.decide","org.rill.preview.feedback","org.rill.preview.inspect"]}}'
    ;;
  health)
    jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"health",healthy:true,status:"healthy",reasonCodes:[]}}'
    ;;
  inspect)
    jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"inspection",summary:{runtimeVersion:"0.2.0-preview",protocolVersion:3,channel:"preview",modelGeneration:2,stateGeneration:9,stateSchemaVersion:2,stateChecksum:"abc",pendingDecisions:1,completedDecisions:8,resourceProfile:{},resourceUtilization:{},rollbackAvailable:false,candidateAvailable:true,health:{status:"healthy"},lastError:null,handler:"preview"}}}'
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$CFIP_RILL_RUNTIME"

status="$(cfip_rill_status_json)"
test "$(jq -r '.available' <<<"$status")" = true
test "$(jq -r '.health' <<<"$status")" = healthy
test "$(jq -r '.healthHealthy' <<<"$status")" = true
test "$(jq -r '.resourcePressure' <<<"$status")" = false
test "$(jq -r '.modelGeneration' <<<"$status")" = 2
test "$(jq -r '.inspect.pendingDecisions' <<<"$status")" = 1

echo 'Rill health and inspect contract passed'
