#!/usr/bin/env bash
set -euo pipefail
BIN="${1:?compiled rill-runtime binary required}"; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/runtime-wrapper" <<EOF_WRAPPER
#!/bin/sh
tee "$TMP/runtime-request.ndjson" | "$BIN" "\$@"
EOF_WRAPPER
chmod +x "$TMP/runtime-wrapper"
export CFIP_RUN_ID=shell-feedback-run CFIP_LOG_FILE="$TMP/log" CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_RILL_RUNTIME="$TMP/runtime-wrapper" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_TIMEOUT_S=5 CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v1.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat >"$TMP/native.json" <<'EOF_NATIVE'
[{"ip":"104.16.1.1","nativeRank":1,"avgLatencyMs":10,"downloadMBps":20,"lossRate":0,"probeSummary":{"connectMs":10,"tlsMs":10,"ttfbMs":20,"totalMs":40},"eligible":true}]
EOF_NATIVE
cat >"$TMP/selected.json" <<'EOF_SELECTED'
[{"ip":"104.16.1.1","family":"ipv4"}]
EOF_SELECTED
cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:true,connectMs:10,tlsMs:10,ttfbMs:20,totalMs:40}'; }
cfip_rill_rank_shadow "$TMP/native.json" "$TMP/rill.json"
jq -e '.generation == 1' "$TMP/rill.json" >/dev/null
jq -e 'select(.request.method=="decide") | .request.context.actions[0].features == [0.01,0.2,0,0.01,0.01,0.02,0.04,0.0078125]' "$TMP/runtime-request.ndjson" >/dev/null
cp "$TMP/rill.json" "$TMP/decision-d1.json"
cat >"$TMP/native-f2.json" <<'EOF_NATIVE_F2'
[{"ip":"104.16.1.1","nativeRank":1,"avgLatencyMs":100,"downloadMBps":2,"lossRate":0.4,"probeSummary":{"connectMs":100,"tlsMs":100,"ttfbMs":200,"totalMs":400},"eligible":true}]
EOF_NATIVE_F2
CFIP_RUN_ID=shell-feedback-run-d2
cfip_rill_rank_shadow "$TMP/native-f2.json" "$TMP/rill-d2.json"
jq -e '.generation == 2' "$TMP/rill-d2.json" >/dev/null
cp "$TMP/rill-d2.json" "$TMP/decision-d2.json"
CFIP_RUN_ID=shell-feedback-run
CFIP_RUN_ID=shell-feedback-run cfip_post_apply_probe "$TMP/selected.json" example.com 5 "$TMP/outcome.json"
jq -e '.validated==true and .ip=="104.16.1.1" and (.reward|type)=="number" and .observedAt>0 and (.appliedIps|length)==1' "$TMP/outcome.json" >/dev/null
cfip_rill_feedback "$TMP/decision-d1.json" "$TMP/outcome.json" | cat >/dev/null
jq -e 'select(.request.method=="feedback") | .request.generation==1 and .modelGeneration==1 and .stateGeneration==2 and .request.selectedActionId=="104.16.1.1"' "$TMP/runtime-request.ndjson" >/dev/null
jq -e '([.partitions[] | select(.clientIdentityName=="cloudflare-ip" and .partitionKey=="default")][0]) as $p | $p.handlerSnapshot.stateGeneration==3 and ($p.handlerSnapshot.state|implode|fromjson).feedback==1 and ($p.handlerSnapshot.state|implode|fromjson).actions["104.16.1.1"].samples==1 and (($p.handlerSnapshot.state|implode|fromjson).weights[0] > 0.00095 and ($p.handlerSnapshot.state|implode|fromjson).weights[0] < 0.00098) and (($p.handlerSnapshot.state|implode|fromjson).weights[1] > 0.0191 and ($p.handlerSnapshot.state|implode|fromjson).weights[1] < 0.0194)' "$CFIP_RILL_STATE" >/dev/null
echo 'shell outcome to compiled Rill Runtime feedback integration passed'
