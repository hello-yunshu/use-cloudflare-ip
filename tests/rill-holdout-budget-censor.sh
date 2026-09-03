#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_HOLDOUT_INTERVAL=1 CFIP_RILL_HOLDOUT_TIMEOUT=1 CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
jq -cn '{decisionId:"budget",effectiveMode:"assisted",nativeOrder:["1.1.1.1"],authorityActionId:"2.2.2.2"}' >"$TMP/decision.json"; jq -cn '[{ip:"1.1.1.1",family:"ipv4",lossRate:0,downloadMBps:20}]' >"$TMP/native.json"; jq -cn '{reward:0.8}' >"$TMP/actual.json"
cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:false,errorClass:"measurement_budget",curlExit:124}'; }
cfip_rill_holdout "$TMP/decision.json" "$TMP/native.json" "$TMP/actual.json" one.example 1 "$TMP/holdout.json"
test "$(jq -r '.performed' "$TMP/holdout.json")" = false; test "$(jq -r '.reason' "$TMP/holdout.json")" = budget_unavailable; test "$(jq -r '.feedbackEligible' "$TMP/holdout.json")" = false; test "$(jq -r '.comparison' "$TMP/holdout.json")" = unavailable
test "$(jq 'has("rewardDelta") or has("nativeHoldoutReward") or has("actualCandidateReward")' "$TMP/holdout.json")" = false
echo 'Holdout measurement-budget exhaustion is censored and never recorded as Native loss'
