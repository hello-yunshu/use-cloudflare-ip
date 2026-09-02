#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
export CFIP_SOURCE_POLICY_FILE="$TMP/source-policy.json" CFIP_SOURCE_POLICY_QUALIFICATION_FILE="$TMP/source-policy-qualification.json"
export CFIP_SOURCE_POLICY=balanced CFIP_RILL_ENABLED=false CFIP_RILL_MODE=off
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"

printf '%s\n' '{"candidateOutcome":"success"}' >"$TMP/outcome.json"
printf '%s\n' '{"decisionId":"native-decision","selectedActionId":"official-heavy"}' >"$TMP/decision.json"
CFIP_SOURCE_POLICY_EXECUTED=balanced CFIP_SOURCE_POLICY_RECOMMENDED=official-heavy CFIP_SOURCE_POLICY_EXPLORATION=false CFIP_SOURCE_POLICY_DECISION_FILE="$TMP/decision.json" \
    cfip_source_policy_record "$TMP/outcome.json"
jq -e '.window[-1] | .nativePolicy == "balanced" and .recommendedAction == "official-heavy" and .executedAction == "balanced" and .disagreement == true and .attributed == false and .evaluatedDisagreement == false' "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE" >/dev/null

printf '%s\n' '{"decisionId":"exploration-decision","selectedActionId":"official-heavy"}' >"$TMP/decision.json"
CFIP_SOURCE_POLICY_EXECUTED=official-heavy CFIP_SOURCE_POLICY_RECOMMENDED=official-heavy CFIP_SOURCE_POLICY_EXPLORATION=true CFIP_SOURCE_POLICY_DECISION_FILE="$TMP/decision.json" \
    cfip_source_policy_record "$TMP/outcome.json"
jq -e '.window[-1] | .nativePolicy == "balanced" and .recommendedAction == "official-heavy" and .executedAction == "official-heavy" and .disagreement == true and .attributed == true and .evaluatedDisagreement == true' "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE" >/dev/null
jq -e '.disagreements == 2 and .attributedFeedback == 1 and .evaluatedDisagreements == 1 and .attributionCoverage == 1' "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE" >/dev/null
echo 'Source policy disagreement and attribution lifecycle passed'
