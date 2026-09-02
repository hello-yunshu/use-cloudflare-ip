#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
export CFIP_SOURCE_POLICY_FILE="$TMP/source-policy.json" CFIP_SOURCE_POLICY_QUALIFICATION_FILE="$TMP/source-policy-qualification.json"
export CFIP_SOURCE_POLICY=balanced CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_SOURCE_POLICY_DECISION_FILE="$TMP/decision.json"
export CFIP_INPUT_POOL_FILE="$TMP/input-pool.json" CFIP_SOURCE_STATUS_FILE="$TMP/source-status.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
printf '%s\n' '{"schemaVersion":2,"policies":{"balanced":{"ewmaReward":0.5,"samples":1}}}' >"$CFIP_SOURCE_POLICY_FILE"
printf '%s\n' '{"candidateOutcome":"success"}' >"$TMP/outcome.json"
printf '%s\n' '[{"ip":"104.16.1.1"}]' >"$CFIP_INPUT_POOL_FILE"
printf '%s\n' '[{"success":true,"stale":false}]' >"$CFIP_SOURCE_STATUS_FILE"
test "$(cfip_source_policy_qualification_json | jq -r '.state')" = cold
feedbacks=0
cfip_rill_policy_feedback() { feedbacks=$((feedbacks + 1)); return 0; }
for i in $(seq 1 5); do
    printf '%s\n' "{\"decisionId\":\"qualification-$i\",\"selectedActionId\":\"official-heavy\"}" >"$CFIP_SOURCE_POLICY_DECISION_FILE"
    CFIP_SOURCE_POLICY_EXECUTED=official-heavy CFIP_SOURCE_POLICY_RECOMMENDED=official-heavy CFIP_SOURCE_POLICY_EXPLORATION=true \
        cfip_source_policy_record "$TMP/outcome.json"
done
test "$(jq -r '.state' "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE")" = evidence
for i in $(seq 6 30); do
    printf '%s\n' "{\"decisionId\":\"qualification-$i\",\"selectedActionId\":\"official-heavy\"}" >"$CFIP_SOURCE_POLICY_DECISION_FILE"
    CFIP_SOURCE_POLICY_EXECUTED=official-heavy CFIP_SOURCE_POLICY_RECOMMENDED=official-heavy CFIP_SOURCE_POLICY_EXPLORATION=true \
        cfip_source_policy_record "$TMP/outcome.json"
done
jq -e '.state == "shadow-qualified" and .windowSamples == 30 and .disagreements == 30 and .attributedFeedback == 30 and .evaluatedDisagreements == 30 and .attributionCoverage == 1 and .recentErrors == 0' "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE" >/dev/null
test "$feedbacks" -eq 30
echo 'Source policy qualification lifecycle passed'
