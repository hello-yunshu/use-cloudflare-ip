#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/rill-evidence.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_MODE=shadow CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
printf '%s\n' '{"decisionId":"evidence","requestedMode":"shadow","effectiveMode":"shadow","nativeOrder":["1.1.1.1"],"rillOrder":["2.2.2.2"],"authorityActionId":"1.1.1.1","nativeRillTop1Agreement":false,"generation":2,"confidenceReasons":["native_authority"]}' >"$TMP/decision.json"
printf '%s\n' '{"reward":0.6,"nativeCounterfactualReward":0.5,"rillShadowReward":0.6,"rewardDelta":0.1,"comparison":"win"}' >"$TMP/outcome.json"
for _ in $(seq 1 70); do cfip_rill_record_evidence "$TMP/decision.json" "$TMP/outcome.json" '{}'; done
test "$(jq 'length' "$CFIP_RILL_EVIDENCE_FILE")" = 64
aggregate="$(cfip_rill_evidence_aggregate_json)"
test "$(jq -r '.comparableDecisions' <<<"$aggregate")" = 64
test "$(jq -r '.wins' <<<"$aggregate")" = 64
test "$(jq -r '.currentContextFingerprint|length' <<<"$aggregate")" = 64
echo 'Bounded persistent evidence store and denominator-safe aggregate passed'
