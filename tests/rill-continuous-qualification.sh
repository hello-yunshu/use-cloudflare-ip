#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_MIN_FEEDBACK_SAMPLES=10
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
printf '%s\n' '{"candidateOutcome":"success","reward":0.8,"nativeCounterfactualReward":0.6,"rillShadowReward":0.8,"rewardDelta":0.2,"disagreement":true}' >"$TMP/good.json"
for _ in $(seq 1 12); do cfip_rill_record_qualification success true true false 0.8 "$TMP/good.json"; done
test "$(jq -r .state "$CFIP_RILL_QUALIFICATION_FILE")" = shadow-qualified
printf '%s\n' '{"candidateOutcome":"success","reward":0.1,"nativeCounterfactualReward":0.8,"rillShadowReward":0.1,"rewardDelta":-0.7,"disagreement":true}' >"$TMP/bad.json"
for _ in $(seq 1 5); do cfip_rill_record_qualification success true true false 0.1 "$TMP/bad.json"; done
test "$(jq -r .state "$CFIP_RILL_QUALIFICATION_FILE")" = shadow
echo 'Continuous qualification conservatively downgrades on rolling negative value'
