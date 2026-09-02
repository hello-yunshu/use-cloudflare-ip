#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
mkdir -p "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/reuse.sh"

CFIP_REUSE_STATE_FILE="$TMP/reuse-policy.json"
CFIP_STATUS_FILE="$TMP/status.json"
CFIP_SELECTED_FILE="$TMP/selected.json"
CFIP_OUTCOME_FILE="$TMP/outcome.json"
CFIP_REUSE_DECISION_FILE="$TMP/decision.json"
CFIP_REUSE_ENABLED=true CFIP_REUSE_MAX_FULL_OPTIMIZE_INTERVAL=86400
CFIP_REUSE_VALIDATION_TIMEOUT=5 CFIP_REUSE_LOSS_LIMIT=0.25
CFIP_REUSE_TTFB_LIMIT=3000 CFIP_REUSE_TOTAL_LIMIT=5000
CFIP_MODE=passwall CFIP_TARGET_DOMAINS='one.example,two.example'
CFIP_IP_TYPE=ipv4 CFIP_SPEEDTEST_PROTOCOL=tcp
CFIP_PASSWALL_TARGET_DOMAIN=one.example CFIP_OPENCLASH_CONFIG=''
CFIP_OPENCLASH_TARGET_DOMAIN='' CFIP_OPENCLASH_TRANSPORT_FILTER=''
CFIP_SOURCE_POLICY=balanced CFIP_IP_COUNT=1

printf '%s\n' '{"best_ips":["104.16.1.1"],"last_result":"success"}' >"$CFIP_STATUS_FILE"
test "$(jq -r '.validationSuccess' < <(cfip_reuse_state_json))" = false
# A genuinely fresh state may first fail on its missing configuration
# fingerprint; the important contract is that it is not reusable.
test -n "$(cfip_reuse_hard_gate_reason)"

# This is the production event emitted only after apply, post-apply probe and
# transaction commit. The next process must be able to reuse it naturally.
cfip_reuse_write_event full-optimize-success full_optimize_completed 0 0
test "$(jq -r '.lastValidationAt > 0 and .validationSuccess == true and .fullOptimizeCount == 1' "$CFIP_REUSE_STATE_FILE")" = true

cfip_post_apply_probe() {
  jq -cn '{candidateOutcome:"success",hostOutcome:"success",censored:false,observedIp:"104.16.1.1",probes:[{success:true,lossRate:0.01,ttfbMs:20,totalMs:50}]}' >"$4"
}
cfip_reuse_try_current
test "$(jq -r '.actualPolicy' "$CFIP_REUSE_DECISION_FILE")" = REUSE_CURRENT
test "$(jq -r '.reuseCount' "$CFIP_REUSE_STATE_FILE")" = 1
test "$(jq -r '.savedProbes' "$CFIP_REUSE_STATE_FILE")" = 1
test "$(jq -r '.validationSuccess' "$CFIP_REUSE_STATE_FILE")" = true
echo 'Reuse fresh full-optimize to current validation lifecycle passed'
