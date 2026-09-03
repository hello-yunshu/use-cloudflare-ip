#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
jq -cn --argjson training "$(jq -cn '[range(0;30)|{evidenceType:"training",attributed:true,delayed:true,error:false,reward:0.8}]')" --argjson evaluation "$(jq -cn '[range(0;12)|{evaluationSource:"holdout",comparisonResult:"win",nativeReward:0.7,rillReward:0.8,rewardDelta:0.1,at:1}]')" '{state:"shadow-qualified",validFeedback:30,attributedFeedback:30,delayedCompleted:30,trainingWindow:$training,window:$training,evaluationWindow:$evaluation,evaluationCount:12}' >"$CFIP_RILL_QUALIFICATION_FILE"
printf '%s\n' '{"candidateOutcome":"success","reward":0.1}' >"$TMP/outcome.json"; printf '%s\n' '{"decisionId":"bad","effectiveMode":"assisted","nativeOrder":["1.1.1.1"],"authorityActionId":"2.2.2.2"}' >"$TMP/decision.json"
for _ in $(seq 1 5); do printf '%s\n' '{"performed":true,"nativeHoldoutReward":0.8,"actualCandidateReward":0.1,"rewardDelta":-0.7,"comparison":"loss","failure":false}' >"$TMP/holdout.json"; cfip_rill_record_evaluation "$TMP/decision.json" "$TMP/outcome.json" "$TMP/holdout.json"; done
test "$(jq -r .state "$CFIP_RILL_QUALIFICATION_FILE")" = shadow; ! cfip_rill_qualified
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_RILL_ENABLED=true CFIP_RILL_MODE=assisted CFIP_IP_COUNT=1 CFIP_RILL_SAFE_TOP_K=2 CFIP_RUN_ID=regression-production CFIP_NATIVE_FILE="$TMP/native.json" CFIP_SELECTED_FILE="$TMP/selected.json" CFIP_RILL_FILE="$TMP/rill.json" CFIP_DECISION_FILE="$TMP/production-decision.json"
printf '%s\n' '[{"ip":"1.1.1.1","family":"ipv4","eligible":true,"lossRate":0,"probeSummary":{"totalMs":40,"ttfbMs":20}}]' >"$CFIP_NATIVE_FILE"; cp "$CFIP_NATIVE_FILE" "$CFIP_SELECTED_FILE"
printf '%s\n' '{"success":true,"selectedActionId":"2.2.2.2","candidates":[{"ip":"2.2.2.2","family":"ipv4","rillRank":1},{"ip":"1.1.1.1","family":"ipv4","rillRank":2}],"generation":1,"decisionId":"regression-production"}' >"$CFIP_RILL_FILE"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=assisted CFIP_IP_COUNT=1 CFIP_RILL_SAFE_TOP_K=2 CFIP_RUN_ID=regression-production CFIP_NATIVE_FILE="$TMP/native.json" CFIP_SELECTED_FILE="$TMP/selected.json" CFIP_RILL_FILE="$TMP/rill.json" CFIP_DECISION_FILE="$TMP/production-decision.json"
build_decision
test "$(jq -r '.requestedMode' "$CFIP_DECISION_FILE")" = assisted; test "$(jq -r '.effectiveMode' "$CFIP_DECISION_FILE")" = shadow; test "$(jq -r '.authorityActionId' "$CFIP_DECISION_FILE")" = 1.1.1.1
echo 'Repeated Native holdout regressions downgrade Assisted to Shadow and next production decision restores Native authority'
