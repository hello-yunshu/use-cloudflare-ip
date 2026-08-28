#!/usr/bin/env bash
set -euo pipefail
BIN="${1:?compiled rill-runtime binary required}"; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_RUN_ID=shell-feedback-run CFIP_LOG_FILE="$TMP/log" CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_RILL_RUNTIME="$BIN" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_TIMEOUT_S=5 CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v1.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat >"$TMP/native.json" <<'EOF_NATIVE'
[{"ip":"104.16.1.1","nativeRank":1,"avgLatencyMs":10,"downloadMBps":20,"lossRate":0,"connectMs":10,"tlsMs":10,"ttfbMs":20,"totalMs":40,"probeSummary":{"totalMs":40},"eligible":true}]
EOF_NATIVE
cat >"$TMP/selected.json" <<'EOF_SELECTED'
[{"ip":"104.16.1.1","family":"ipv4"}]
EOF_SELECTED
cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:true,totalMs:40,connectMs:10,tlsMs:10,ttfbMs:20}'; }
cfip_rill_rank_shadow "$TMP/native.json" "$TMP/rill.json"
jq -e '.generation == 1' "$TMP/rill.json" >/dev/null
jq --arg runId "$CFIP_RUN_ID" --argjson generation "$(jq '.generation' "$TMP/rill.json")" '{schemaVersion:1,runId:$runId,decisionId:.decisionId,selectedActionId:.selectedActionId,generation:$generation}' "$TMP/rill.json" >"$TMP/decision.json"
CFIP_RUN_ID=shell-feedback-run cfip_post_apply_probe "$TMP/selected.json" example.com 5 "$TMP/outcome.json"
jq -e '.validated==true and .ip=="104.16.1.1" and (.reward|type)=="number" and .observedAt>0 and (.appliedIps|length)==1' "$TMP/outcome.json" >/dev/null
cfip_rill_feedback "$TMP/decision.json" "$TMP/outcome.json" | cat >/dev/null
jq -e '.handlerSnapshot.stateGeneration==2 and (.handlerSnapshot.state|implode|fromjson).feedback==1 and (.handlerSnapshot.state|implode|fromjson).actions["104.16.1.1"].samples==1' "$CFIP_RILL_STATE" >/dev/null
echo 'shell outcome to compiled Rill Runtime feedback integration passed'
