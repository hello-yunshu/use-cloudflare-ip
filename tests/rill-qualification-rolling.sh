#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_LOG_FILE="$TMP/log"
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
export CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

cat >"$TMP/outcome.json" <<'JSON'
{"candidateOutcome":"success","reward":0.7,"nativeCounterfactualReward":0.6,"rillShadowReward":0.7,"rewardDelta":0.1,"disagreement":true}
JSON
for _ in $(seq 1 40); do
  cfip_rill_record_qualification success true true false 0.7 "$TMP/outcome.json"
done
test "$(jq -r '.state' "$CFIP_RILL_QUALIFICATION_FILE")" = shadow-qualified
test "$(jq -r '.window|length' "$CFIP_RILL_QUALIFICATION_FILE")" = 40
test "$(jq -r '.disagreements' "$CFIP_RILL_QUALIFICATION_FILE")" = 40
test "$(jq -r '.disagreementWin' "$CFIP_RILL_QUALIFICATION_FILE")" = 40

cat >"$TMP/error-outcome.json" <<'JSON'
{"candidateOutcome":"success","reward":0.7,"nativeCounterfactualReward":0.6,"rillShadowReward":0.7,"rewardDelta":0.1,"disagreement":true}
JSON
for _ in $(seq 1 5); do
  cfip_rill_record_qualification success false false true 0.7 "$TMP/error-outcome.json"
done
test "$(jq -r '.state' "$CFIP_RILL_QUALIFICATION_FILE")" = shadow
test "$(jq -r '.window|length' "$CFIP_RILL_QUALIFICATION_FILE")" = 45
echo 'Rill rolling qualification and automatic downgrade contract passed'
