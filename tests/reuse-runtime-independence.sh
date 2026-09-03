#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
mkdir -p "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/reuse.sh"
CFIP_REUSE_STATE_FILE="$TMP/reuse.json"; CFIP_STATUS_FILE="$TMP/status.json"; CFIP_SELECTED_FILE="$TMP/selected.json"; CFIP_OUTCOME_FILE="$TMP/outcome.json"; CFIP_REUSE_DECISION_FILE="$TMP/decision.json"; CFIP_RILL_STATE_META_FILE="$TMP/rill-state-meta.json"
CFIP_REUSE_ENABLED=true CFIP_REUSE_MAX_FULL_OPTIMIZE_INTERVAL=86400 CFIP_REUSE_VALIDATION_TIMEOUT=5 CFIP_REUSE_LOSS_LIMIT=0.25 CFIP_REUSE_TTFB_LIMIT=3000 CFIP_REUSE_TOTAL_LIMIT=5000 CFIP_MODE=passwall CFIP_TARGET_DOMAINS='one.example' CFIP_IP_TYPE=ipv4 CFIP_SPEEDTEST_PROTOCOL=tcp CFIP_IP_COUNT=1
printf '%s\n' '{"best_ips":["104.16.1.1"],"last_result":"success"}' > "$CFIP_STATUS_FILE"
fp="$(cfip_reuse_config_fingerprint)"
printf '%s\n' '{"resetRequired":true,"resetReason":"corrupt_candidate_state"}' > "$CFIP_RILL_STATE_META_FILE"
jq -cn --arg fp "$fp" '{schemaVersion:1,lastFullOptimizeAt:(now|floor),lastValidationAt:(now|floor),validationSuccess:true,configFingerprint:$fp,reuseCount:0,fullOptimizeCount:1,savedProbes:0,savedRuntimeSeconds:0,recent:[]}' > "$CFIP_REUSE_STATE_FILE"
test "$(cfip_reuse_hard_gate_reason)" = ''
cfip_post_apply_probe() { jq -cn '{candidateOutcome:"success",hostOutcome:"success",censored:false,observedIp:"104.16.1.1",probes:[{success:true,lossRate:0.01,ttfbMs:20,totalMs:50}]}' > "$4"; }
cfip_reuse_try_current
test "$(jq -r '.actualPolicy' "$CFIP_REUSE_DECISION_FILE")" = REUSE_CURRENT
echo 'Native Reuse remains independent of Candidate Runtime reset state'
