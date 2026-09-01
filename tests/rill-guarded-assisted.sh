#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
mkdir -p "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"

export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=assisted CFIP_RILL_SAFE_TOP_K=2 CFIP_IP_COUNT=1
export CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_HISTORY_FILE="$TMP/history.json"
CFIP_NATIVE_FILE="$TMP/native.json" CFIP_RILL_FILE="$TMP/rill.json"
printf '%s\n' '{"state":"shadow-qualified","validFeedback":40,"attributedFeedback":40,"delayedCompleted":40,"errors":0}' > "$CFIP_RILL_QUALIFICATION_FILE"
printf '%s\n' '{"203.0.113.9":{"consecutiveFailures":0}}' > "$CFIP_RILL_HISTORY_FILE"
cat > "$CFIP_NATIVE_FILE" <<'JSON'
[
  {"ip":"104.16.1.1","nativeRank":1,"eligible":true,"lossRate":0.01,"probeSummary":{"ttfbMs":100,"totalMs":500}},
  {"ip":"104.16.1.2","nativeRank":2,"eligible":true,"lossRate":0.01,"probeSummary":{"ttfbMs":100,"totalMs":500}},
  {"ip":"203.0.113.9","nativeRank":3,"eligible":true,"lossRate":0.01,"probeSummary":{"ttfbMs":100,"totalMs":500}}
]
JSON
cat > "$CFIP_RILL_FILE" <<'JSON'
{"success":true,"decisionId":"assisted-test","selectedActionId":"203.0.113.9","generation":4,"candidates":[
  {"ip":"203.0.113.9","rillRank":1,"rillScore":0.99},
  {"ip":"104.16.1.2","rillRank":2,"rillScore":0.80},
  {"ip":"104.16.1.1","rillRank":3,"rillScore":0.70}
]}
JSON
CFIP_SELECTED_FILE="$TMP/selected.json"
select_assisted_candidates
test "$(jq -r '.[0].ip' "$CFIP_SELECTED_FILE")" = 104.16.1.2

CFIP_DECISION_FILE="$TMP/decision.json"
build_decision
test "$(jq -r .effectiveMode "$CFIP_DECISION_FILE")" = assisted
test "$(jq -r .selectedActionId "$CFIP_DECISION_FILE")" = 104.16.1.2
test "$(jq -r .authorityActionId "$CFIP_DECISION_FILE")" = 104.16.1.2
test "$(jq -r .rillSelectedActionId "$CFIP_DECISION_FILE")" = 203.0.113.9
test "$(jq -r .rillTop3Overlap "$CFIP_DECISION_FILE")" = 3
echo 'Rill guarded assisted envelope tests passed'
