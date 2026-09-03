#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_TARGET_DOMAINS=one.example CFIP_RILL_HOLDOUT_INTERVAL=1
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
printf '%s\n' '{"decisionId":"evaluation-only","effectiveMode":"assisted","nativeOrder":["1.1.1.1"],"authorityActionId":"2.2.2.2","confidenceLevel":"high","confidenceReasons":["qualification_valid"]}' >"$TMP/decision.json"; printf '%s\n' '{"reward":0.8,"candidateOutcome":"success"}' >"$TMP/outcome.json"; printf '%s\n' '{"performed":true,"nativeHoldoutReward":0.7,"actualCandidateReward":0.8,"rewardDelta":0.1,"comparison":"win","failure":false,"feedbackEligible":false}' >"$TMP/holdout.json"
feedback_calls=0; cfip_rill_feedback() { feedback_calls=$((feedback_calls+1)); return 99; }
cfip_rill_record_evidence "$TMP/decision.json" "$TMP/outcome.json" "$TMP/holdout.json"
test "$feedback_calls" = 0; test "$(jq -r '.[-1].feedbackEligible' "$CFIP_RILL_EVIDENCE_FILE")" = false; test "$(jq -r '.evaluationCount' "$CFIP_RILL_QUALIFICATION_FILE")" = 1
echo 'Native Holdout updates Evaluation only and never calls Runtime feedback'
