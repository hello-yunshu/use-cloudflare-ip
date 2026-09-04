#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
mkdir -p "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=assisted CFIP_RILL_SAFE_TOP_K=3 CFIP_IP_COUNT=1
export CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_HISTORY_FILE="$TMP/history.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
CFIP_NATIVE_FILE="$TMP/native.json"; CFIP_RILL_FILE="$TMP/rill.json"; CFIP_SELECTED_FILE="$TMP/selected.json"; CFIP_DECISION_FILE="$TMP/decision.json"
printf '%s\n' '{"state":"shadow-qualified","validFeedback":40,"attributedFeedback":40,"delayedCompleted":40,"errors":0}' | jq '. + {evaluationHealth:"healthy",evaluationFreshAt:(now|floor)}' > "$CFIP_RILL_QUALIFICATION_FILE"
printf '%s\n' '{}'
cat > "$CFIP_NATIVE_FILE" <<'JSON'
[{"ip":"104.16.1.1","family":"ipv4","nativeRank":1,"eligible":true,"lossRate":0.01,"probeSummary":{"ttfbMs":100,"totalMs":500}},
 {"ip":"104.16.1.2","family":"ipv4","nativeRank":2,"eligible":true,"lossRate":0.01,"probeSummary":{"ttfbMs":100,"totalMs":500}}]
JSON
cat > "$CFIP_RILL_FILE" <<'JSON'
{"success":true,"decisionId":"fallback-test","selectedActionId":"104.16.1.2","generation":4,"candidates":[{"ip":"104.16.1.2","rillRank":1,"rillScore":0.99},{"ip":"104.16.1.1","rillRank":2,"rillScore":0.80}]}
JSON
printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"}]' > "$CFIP_SELECTED_FILE"
cfip_rill_status_json() { jq -cn --arg schema "$(sha256sum "$CFIP_RILL_SCHEMA_FILE" | awk '{print $1}')" '{available:true,state:"degraded",health:"unhealthy",healthHealthy:false,resourcePressure:false,featureSchemaVersion:2,featureSchemaHash:$schema,modelGeneration:2,qualificationState:"shadow-qualified",resetRequired:false}'; }
select_assisted_candidates
test "$(jq -r '.[0].ip' "$CFIP_SELECTED_FILE")" = 104.16.1.1
build_decision
test "$(jq -r '.effectiveMode' "$CFIP_DECISION_FILE")" = shadow
test "$(jq -r '.fallbackReason' "$CFIP_DECISION_FILE")" = runtime_unhealthy
test "$(jq -r '.authorityActionId' "$CFIP_DECISION_FILE")" = 104.16.1.1
cfip_txn_apply() { test "$(jq -r '.[0].ip' "$2")" = 104.16.1.1; }
cfip_txn_apply passwall "$CFIP_SELECTED_FILE"
echo 'Assisted unhealthy fallback preserves Native transaction selection'
