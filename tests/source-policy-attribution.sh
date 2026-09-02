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
printf '%s\n' '{"decisionId":"d-native","selectedActionId":"official-heavy"}' >"$TMP/decision.json"
CFIP_SOURCE_POLICY_EFFECTIVE=balanced CFIP_SOURCE_POLICY_EXECUTED=balanced CFIP_SOURCE_POLICY_RECOMMENDED=official-heavy CFIP_SOURCE_POLICY_EXPLORATION=false CFIP_SOURCE_POLICY_DECISION_FILE="$TMP/decision.json" \
  cfip_source_policy_record "$TMP/outcome.json"
jq -e '.disagreements == 1 and .attributedFeedback == 0 and .evaluatedDisagreements == 0 and .qualificationState == "learning" and .window[-1].recommendedAction == "official-heavy" and .window[-1].executedAction == "balanced" and .window[-1].attributed == false' "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE" >/dev/null

printf '%s\n' '{"decisionId":"d-explore","selectedActionId":"official-heavy"}' >"$TMP/decision.json"
CFIP_SOURCE_POLICY_EFFECTIVE=official-heavy CFIP_SOURCE_POLICY_EXECUTED=official-heavy CFIP_SOURCE_POLICY_RECOMMENDED=official-heavy CFIP_SOURCE_POLICY_EXPLORATION=true CFIP_SOURCE_POLICY_DECISION_FILE="$TMP/decision.json" \
  cfip_source_policy_record "$TMP/outcome.json"
jq -e '.window[-1].decisionId == "d-explore" and .window[-1].recommendedAction == "official-heavy" and .window[-1].executedAction == "official-heavy" and .window[-1].attributed == true and (.attributionCoverage > 0)' "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE" >/dev/null
echo 'Source policy attribution and disagreement contract passed'
