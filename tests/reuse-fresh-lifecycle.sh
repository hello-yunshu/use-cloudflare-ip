#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export TMP CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
mkdir -p "$CFIP_STATUS_DIR" "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
export CFST_COUNT_FILE="$TMP/cfst-runs" POOL_COUNT_FILE="$TMP/pool-runs" PROBE_COUNT_FILE="$TMP/probe-runs"

CFIP_REUSE_STATE_FILE="$CFIP_STATUS_DIR/reuse-policy.json"
CFIP_STATUS_FILE="$CFIP_STATUS_DIR/status.json"
CFIP_REUSE_ENABLED=true CFIP_REUSE_MAX_FULL_OPTIMIZE_INTERVAL=86400
CFIP_REUSE_VALIDATION_TIMEOUT=5 CFIP_REUSE_LOSS_LIMIT=0.25
CFIP_REUSE_TTFB_LIMIT=3000 CFIP_REUSE_TOTAL_LIMIT=5000
CFIP_SOURCE_POLICY=balanced CFIP_IP_COUNT=1
CFIP_RUN_NUMBER=0

load_config() {
    CFIP_STATUS_FILE="$CFIP_STATUS_DIR/status.json" CFIP_RUN_HISTORY="$CFIP_STATUS_DIR/run-history.ndjson" CFIP_REUSE_STATE_FILE="$CFIP_STATUS_DIR/reuse-policy.json" CFIP_ADAPTIVE_STATE_FILE="$CFIP_STATUS_DIR/adaptive-measurement-state.json" CFIP_ADAPTIVE_EVIDENCE_FILE="$CFIP_STATUS_DIR/adaptive-measurement-evidence.json" CFIP_ADAPTIVE_SCHEDULER_VERSION=1 CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION=1
    CFIP_ENABLED=true CFIP_MODE=passwall CFIP_IP_COUNT=1 CFIP_IP_TYPE=ipv4
    CFIP_SPEEDTEST_PROTOCOL=tcp CFIP_SPEEDTEST_CFCOLO='' CFIP_SPEEDTEST_DN=8 CFIP_SPEEDTEST_DT=6
    CFIP_SPEEDTEST_TLL=40 CFIP_SPEEDTEST_TL='' CFIP_SPEEDTEST_THREADS=1 CFIP_SPEEDTEST_PING_COUNT=1
    CFIP_STOP_SERVICE=false CFIP_STARTUP_DELAY='' CFIP_WORK_DIR="$TMP/work" CFIP_CRON_INTERVAL=6h
    CFIP_CANDIDATE_BUDGET=128 CFIP_PROBE_TOP_COUNT=1 CFIP_PROBE_CONCURRENCY=1 CFIP_PROBE_TIMEOUT=5
    CFIP_MEASUREMENT_TIMEOUT=60 CFIP_RECOVERY_TIMEOUT=30 CFIP_PROBE_BATCH_SIZE=1 CFIP_MAX_PROBE_COUNT=1
    CFIP_EARLY_STOP_ENABLED=true CFIP_BUILTIN_SOURCES='cloudflare-official-v4' CFIP_SOURCE_POLICY=balanced
    CFIP_TARGET_DOMAINS='one.example' CFIP_PASSWALL_TARGET_DOMAIN=one.example
    CFIP_RILL_ENABLED=false CFIP_RILL_MODE=off CFIP_RILL_SAFE_TOP_K=3 CFIP_RILL_MIN_FEEDBACK_SAMPLES=30 CFIP_RILL_DELAYED_FEEDBACK_SECONDS=600 CFIP_ADAPTIVE_MEASUREMENT_ENABLED=false CFIP_ADAPTIVE_MEASUREMENT_MODE=off CFIP_REUSE_ENABLED=true CFIP_REUSE_MAX_FULL_OPTIMIZE_INTERVAL=86400 CFIP_REUSE_VALIDATION_TIMEOUT=5 CFIP_REUSE_LOSS_LIMIT=0.25 CFIP_REUSE_TTFB_LIMIT=3000 CFIP_REUSE_TOTAL_LIMIT=5000
    return 0
}
acquire_lock() { return 0; }
release_lock() { :; }
cleanup_run_files() { :; }
init_run_paths() {
    CFIP_RUN_NUMBER=$(( ${CFIP_RUN_NUMBER:-0} + 1 )); CFIP_RUN_ID="lifecycle-${CFIP_PROCESS_ID:-$CFIP_RUN_NUMBER}"
    local d="$CFIP_RUNTIME_DIR/run-$CFIP_RUN_ID"
    mkdir -p "$d"
    CFIP_INPUT_POOL_FILE="$d/input-pool.json" CFIP_CANDIDATE_INPUT_FILE="$d/cfst-input.txt"
    CFIP_PROBE_INPUT_FILE="$d/probe-input.json" CFIP_CANDIDATES_FILE="$d/candidates.json"
    CFIP_PROBED_FILE="$d/probed.json" CFIP_NATIVE_FILE="$d/native.json" CFIP_SELECTED_FILE="$d/selected.json"
    CFIP_RILL_FILE="$d/rill.json" CFIP_DECISION_FILE="$d/decision.json" CFIP_OUTCOME_FILE="$d/outcome.json"
    CFIP_TXN_RESULT_FILE="$d/transaction.json" CFIP_SOURCE_STATUS_FILE="$d/source-status.json"
    CFIP_PROBE_METRICS_FILE="$d/probe-metrics.json"
    CFIP_REUSE_DECISION_FILE="$d/reuse-decision.json"
    CFIP_ADAPTIVE_PLAN_FILE="$d/adaptive-plan.json" CFIP_ADAPTIVE_PROBE_INPUT_FILE="$d/adaptive-probe-input.json" CFIP_ADAPTIVE_AUDIT_FILE="$d/adaptive-audit.json"
}
write_status() {
    local best='[]'
    if [[ -s "${CFIP_SELECTED_FILE:-}" ]]; then
        best="$(jq '[.[].ip]' "$CFIP_SELECTED_FILE")"
    elif [[ -s "$CFIP_STATUS_FILE" ]]; then
        best="$(jq -c '.best_ips // []' "$CFIP_STATUS_FILE")"
    fi
    jq -cn --arg result "$3" --arg phase "$2" --argjson best "$best" '{last_result:$result,phase:$phase,best_ips:$best}' >"$CFIP_STATUS_FILE"
}
ensure_cfst() { printf '1\n' >>"$CFST_COUNT_FILE"; return 0; }
cfip_prepare_candidate_pool() {
    printf '1\n' >>"$POOL_COUNT_FILE"
    printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4","sourceClass":"official","sourceCount":1,"stale":false}]' >"$1"
    printf '%s\n' '104.16.1.1' >"$2"
    printf '%s\n' '[{"success":true,"stale":false}]' >"$3"
}
run_cfst() {
    printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4","cfstRank":1,"downloadMBps":80,"eligible":true,"probeSummary":{"totalMs":50,"ttfbMs":20},"lossRate":0}]' >"$CFIP_CANDIDATES_FILE"
}
cfip_rill_probe_priority() { cp "$1" "$2"; }
cfip_probe_candidates_batched() { cp "$1" "$2"; printf '1\n' >>"$PROBE_COUNT_FILE"; }
cfip_rill_update_history() { :; }
cfip_txn_prepare() { :; }
cfip_txn_apply() { :; }
cfip_txn_commit() { :; }
cfip_txn_rollback() { :; }
cfip_post_apply_probe() {
    jq -cn '{candidateOutcome:"success",hostOutcome:"success",censored:false,observedIp:"104.16.1.1",probes:[{success:true,lossRate:0.01,ttfbMs:20,totalMs:50}]}' >"$4"
}
cfip_rill_queue_feedback() { :; }
cfip_publish_result() { :; }

for function_name in $(declare -F | awk '{print $3}'); do
    export -f "$function_name"
done
export CFIP_RUN_NUMBER=0

# Each phase is a fresh Bash process. The only state shared between them is the
# persisted status/reuse files, which proves reuse survives a daemon restart.
CFIP_PROCESS_ID=A bash -c 'load_config; run_v2 >/dev/null'
test "$(wc -l <"$CFST_COUNT_FILE" | tr -d ' ')" -eq 1
test "$(wc -l <"$POOL_COUNT_FILE" | tr -d ' ')" -eq 1
test "$(wc -l <"$PROBE_COUNT_FILE" | tr -d ' ')" -eq 1
jq -e '.fullOptimizeCount == 1 and .validationSuccess == true' "$CFIP_REUSE_STATE_FILE" >/dev/null
jq -e '.last_result == "success" and .best_ips == ["104.16.1.1"]' "$CFIP_STATUS_FILE" >/dev/null

CFIP_PROCESS_ID=B bash -c 'load_config; run_v2 >/dev/null'
test "$(wc -l <"$CFST_COUNT_FILE" | tr -d ' ')" -eq 1
test "$(wc -l <"$POOL_COUNT_FILE" | tr -d ' ')" -eq 1
test "$(wc -l <"$PROBE_COUNT_FILE" | tr -d ' ')" -eq 1
jq -e '.reuseCount == 1 and .fullOptimizeCount == 1 and .validationSuccess == true' "$CFIP_REUSE_STATE_FILE" >/dev/null
jq -e '.decisionKind == "native-reuse" and .actualPolicy == "REUSE_CURRENT" and .reason == "validated_current_ip"' "$CFIP_RUNTIME_DIR/run-lifecycle-B/reuse-decision.json" >/dev/null
echo 'Reuse lifecycle executes full optimize once then real current-IP reuse'
