#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_STATUS_DIR="$TMP" CFIP_RILL_ENABLED=true CFIP_RILL_MODE=assisted CFIP_RILL_SAFE_TOP_K=3 CFIP_IP_COUNT=1
export CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
CFIP_RILL_ENABLED=true; CFIP_RILL_MODE=assisted; CFIP_RILL_SAFE_TOP_K=3; CFIP_IP_COUNT=1; CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json"; CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
CFIP_NATIVE_FILE="$TMP/native.json"; CFIP_SELECTED_FILE="$TMP/selected.json"; CFIP_RILL_FILE="$TMP/rill.json"; CFIP_DECISION_FILE="$TMP/decision.json"
printf '%s\n' '{"state":"shadow-qualified","validFeedback":40,"attributedFeedback":40,"delayedCompleted":40,"errors":0}' | jq '. + {evaluationHealth:"healthy",evaluationFreshAt:(now|floor)}' >"$CFIP_RILL_QUALIFICATION_FILE"
printf '%s\n' '[{"ip":"104.16.1.1","eligible":true,"lossRate":0,"probeSummary":{"ttfbMs":10,"totalMs":20}}]' >"$CFIP_NATIVE_FILE"
printf '%s\n' '[{"ip":"104.16.1.1"}]' >"$CFIP_SELECTED_FILE"
printf '%s\n' '{"success":true,"decisionId":"confidence","selectedActionId":"104.16.1.1","candidates":[{"ip":"104.16.1.1","rillRank":1}]}' >"$CFIP_RILL_FILE"
cfip_rill_status_json() { jq -cn --arg schema "$(sha256sum "$CFIP_RILL_SCHEMA_FILE" | awk '{print $1}')" '{available:true,state:"healthy",health:"healthy",healthHealthy:true,resourcePressure:false,featureSchemaVersion:2,featureSchemaHash:$schema,modelGeneration:2,qualificationState:"shadow-qualified",resetRequired:false}'; }
build_decision; test "$(jq -r .confidenceLevel "$CFIP_DECISION_FILE")" = high; test "$(jq -r '.confidenceReasons|length' "$CFIP_DECISION_FILE")" -ge 3
CFIP_RILL_MODE=shadow; build_decision; test "$(jq -r .confidenceLevel "$CFIP_DECISION_FILE")" = medium
CFIP_RILL_ENABLED=false; CFIP_RILL_MODE=off; build_decision; test "$(jq -r .confidenceLevel "$CFIP_DECISION_FILE")" = low
echo 'Per-decision confidence is categorical evidence, never a score-as-probability'
