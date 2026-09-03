#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
printf '%s\n' '{"decisionId":"confidence-source","effectiveMode":"assisted","nativeOrder":["1.1.1.1"],"authorityActionId":"2.2.2.2","confidenceLevel":"high","confidenceReasons":["qualification_valid","runtime_healthy"]}' >"$TMP/decision.json"; printf '%s\n' '{"reward":0.8,"candidateOutcome":"success"}' >"$TMP/outcome.json"; printf '%s\n' '{"performed":true,"nativeHoldoutReward":0.7,"actualCandidateReward":0.8,"rewardDelta":0.1,"comparison":"win","failure":false}' >"$TMP/holdout.json"
cfip_rill_record_evidence "$TMP/decision.json" "$TMP/outcome.json" "$TMP/holdout.json"
test "$(jq -r '.[-1].confidenceLevel' "$CFIP_RILL_EVIDENCE_FILE")" = high; test "$(jq -r '.lastDecisionConfidenceLevel' "$CFIP_RILL_QUALIFICATION_FILE")" = high; test "$(jq -c '.[-1].confidenceReasons' "$CFIP_RILL_EVIDENCE_FILE")" = '["qualification_valid","runtime_healthy"]'; test "$(jq -c '.lastDecisionConfidenceReasons' "$CFIP_RILL_QUALIFICATION_FILE")" = '["qualification_valid","runtime_healthy"]'
echo 'Decision, evidence, and status confidence use one source of truth'
