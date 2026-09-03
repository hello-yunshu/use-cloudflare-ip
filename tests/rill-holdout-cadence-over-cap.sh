#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_RILL_HOLDOUT_INTERVAL=5 CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
due=()
for n in $(seq 1 130); do
    jq -cn --arg id "decision-$n" '{decisionId:$id,effectiveMode:"assisted",nativeOrder:["E"],authorityActionId:"R"}' >"$TMP/decision.json"
    if cfip_rill_holdout_due "$TMP/decision.json"; then due+=("$n"); fi
    jq -cn --argjson n "$n" '[range(0;64)|{sequence:$n}]' >"$CFIP_RILL_EVIDENCE_FILE"
done
test "${#due[@]}" = 26
test "${due[*]}" = '5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130'
test "$(jq -r '.assistedDisagreementCount' "$CFIP_RILL_HOLDOUT_STATE_FILE")" = 130
test "$(jq 'length' "$CFIP_RILL_EVIDENCE_FILE")" -le 64
test "$(wc -c <"$CFIP_RILL_EVIDENCE_FILE")" -le "${CFIP_RILL_EVIDENCE_MAX_BYTES:-262144}"
CFIP_TARGET_DOMAINS=two.example; cfip_rill_context_guard
jq -cn '{decisionId:"after-context",effectiveMode:"assisted",nativeOrder:["E"],authorityActionId:"R"}' >"$TMP/decision.json"
if cfip_rill_holdout_due "$TMP/decision.json"; then exit 1; fi
test "$(jq -r '.assistedDisagreementCount' "$CFIP_RILL_HOLDOUT_STATE_FILE")" = 1
echo 'Holdout cadence remains every fifth decision past evidence caps and resets on context lineage rotation'
