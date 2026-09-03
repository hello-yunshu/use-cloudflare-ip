#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json"
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

printf '%s\n' '{"decisionId":"shadow-failure","selectedActionId":"1.1.1.1"}' >"$TMP/decision.json"
printf '%s\n' '{"success":true,"candidates":[{"ip":"1.1.1.1","family":"ipv4","rillRank":1}]}' >"$TMP/rill.json"
printf '%s\n' '{"reward":0.8,"candidateOutcome":"success"}' >"$TMP/native.json"
cfip_probe_one() { return 1; }
if cfip_rill_shadow_observe "$TMP/decision.json" "$TMP/rill.json" one.example 1 "$TMP/shadow.json" "$TMP/native.json"; then
    echo 'unavailable shadow observation unexpectedly succeeded' >&2
    exit 1
fi
printf '%s\n' '{"feedbackEligible":false,"observationUnavailable":true}' >"$TMP/unavailable.json"
cfip_rill_queue_feedback "$TMP/decision.json" "$TMP/unavailable.json" one.example
test ! -e "$TMP/rill-pending-feedback.json"
echo 'Shadow observation failure is fail-closed and does not queue Candidate feedback'
