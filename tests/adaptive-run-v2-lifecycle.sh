#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then cat "$TMP/log" 2>/dev/null || true; fi; rm -rf "$TMP"; exit "$rc"' EXIT
mkdir -p "$TMP/bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$TMP/bin/uci"; chmod +x "$TMP/bin/uci"
export PATH="$TMP/bin:$PATH"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_STATUS_DIR="$TMP/state" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log" CFIP_INIT_DIR="$TMP/init" CFIP_SKIP_STARTUP_DELAY=true
mkdir -p "$CFIP_STATUS_DIR" "$CFIP_RUNTIME_DIR" "$CFIP_INIT_DIR"
export CFIP_VALIDATE_CANDIDATE_JSON='{"cf_ip.main.enabled":"1","cf_ip.main.mode":"passwall","cf_ip.main.ip_count":"1","cf_ip.main.ip_type":"ipv4","cf_ip.main.speedtest_protocol":"tcp","cf_ip.main.measurement_timeout":"20","cf_ip.main.candidate_budget":"100","cf_ip.main.probe_top_count":"3","cf_ip.main.probe_concurrency":"1","cf_ip.main.probe_timeout":"1","cf_ip.main.probe_batch_size":"1","cf_ip.main.max_probe_count":"3","cf_ip.main.source_policy":"balanced","cf_ip.main.reuse_enabled":"0","cf_ip.main.stop_service":"0","cf_ip.main.cron_interval":"1h","cf_ip.main.adaptive_measurement_enabled":"1","cf_ip.main.adaptive_measurement_mode":"shadow","cf_ip.main.adaptive_target_ratio_percent":"50","cf_ip.main.adaptive_min_probe_count":"1","cf_ip.main.adaptive_exploration_ratio_percent":"0","cf_ip.main.adaptive_min_evidence":"1","cf_ip.main.adaptive_evidence_window":"2","cf_ip.main.adaptive_evaluation_max_age_seconds":"604800","cf_ip.main.adaptive_audit_interval":"2","cf_ip.main.adaptive_max_probe_count":"3","cf_ip.main.adaptive_expansion_batch_size":"1","cf_ip.passwall.target_domain":"one.example","cf_ip.rill.enabled":"0","cf_ip.rill.mode":"shadow"}'

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
ensure_cfst() { :; }
cfip_prepare_candidate_pool() {
    printf '%s\n' '[{"ip":"1.1.1.1","family":"ipv4"},{"ip":"1.1.1.2","family":"ipv4"},{"ip":"1.1.1.3","family":"ipv4"}]' >"$1"
    printf '%s\n' '1.1.1.1' '1.1.1.2' '1.1.1.3' >"$2"
    printf '%s\n' '[]' >"$3"
}
run_cfst() { printf '%s\n' '[{"ip":"1.1.1.1","family":"ipv4","cfstRank":1},{"ip":"1.1.1.2","family":"ipv4","cfstRank":2},{"ip":"1.1.1.3","family":"ipv4","cfstRank":3}]' >"$CFIP_CANDIDATES_FILE"; }
cfip_rill_probe_priority() { cp "$1" "$2"; }
probe_fixture() { jq 'map(. + {eligible:true,lossRate:0,downloadMBps:20,probes:[{errorClass:"none"}],probeSummary:{probeCount:1,successCount:1,totalMs:40,ttfbMs:20}})' "$1" >"$2"; }
cfip_probe_candidates() { probe_fixture "$1" "$2"; }
cfip_probe_candidates_batched() { probe_fixture "$1" "$2"; }
cfip_rill_update_history() { :; }
cfip_reuse_try_current() { return 1; }
cfip_reuse_write_event() { :; }
cfip_publish_result() { :; }
write_status() { :; }
remember_history() { :; }
cfip_txn_prepare() { CFIP_TXN_DIR="$TMP/txn"; mkdir -p "$CFIP_TXN_DIR"; CFIP_TXN_MODE="$1"; CFIP_TXN_COMMITTED=false; }
TXN_FAIL=false
cfip_txn_apply() { [[ "$TXN_FAIL" == true ]] && return 9; :; }
cfip_txn_commit() { CFIP_TXN_COMMITTED=true; CFIP_TXN_STATE=COMMITTED; CFIP_TXN_DIR=""; }
cfip_txn_rollback() { :; }
cfip_post_apply_probe() { local selected="$1"; jq -cn --arg ip "$(jq -r '.[0].ip' "$selected")" '{schemaVersion:2,validated:true,candidateOutcome:"success",hostOutcome:"success",censored:false,observedIp:$ip,decisionActionId:$ip,probes:[{ip:$ip,success:true,totalMs:40,ttfbMs:20}]}' >"$4"; }

run_one() { run_v2 >/dev/null; ls -td "$CFIP_RUNTIME_DIR"/run-* | head -n1; }

first="$(run_one)"
test "$(jq -r '.effectiveMode' "$first/decision.json")" = off
test "$(jq -r '.auditRun' "$first/probe-metrics.json")" = false
second="$(run_one)"
test "$(jq -r '.auditRun' "$second/probe-metrics.json")" = true
test "$(jq -r '.transactionApplied' "$second/adaptive-audit.json")" = true
test "$(jq -r '.finalSelectedCandidates[0]' "$second/adaptive-audit.json")" = 1.1.1.1
test "$(jq -r '.appliedCandidates[0]' "$second/adaptive-audit.json")" = 1.1.1.1
test "$(jq -r '.qualificationState' "$CFIP_STATUS_DIR/adaptive-measurement-state.json")" = qualified
test "$(jq -r '.measurementDurationMs | type' "$second/probe-metrics.json")" = number
test "$(jq -r '.fullCandidateCount' "$second/probe-metrics.json")" = 3
test "$(jq -r '.plannedK' "$second/probe-metrics.json")" = 2
test "$(jq -r '.actualUniqueProbeCount' "$second/probe-metrics.json")" = 3
test "$(jq -r '.expansionCount' "$second/probe-metrics.json")" = 0
test "$(jq -r '.fallbackUsed' "$second/probe-metrics.json")" = false
test "$(jq -r '.effectiveAdaptiveMode' "$second/probe-metrics.json")" = shadow
test "$(jq -r '.effectiveCandidateMode' "$second/probe-metrics.json")" = shadow

export CFIP_VALIDATE_CANDIDATE_JSON="$(printf '%s' "$CFIP_VALIDATE_CANDIDATE_JSON" | sed 's/"cf_ip.main.adaptive_measurement_mode":"shadow"/"cf_ip.main.adaptive_measurement_mode":"guarded"/')"
third="$(run_one)"
test "$(jq -r '.effectiveAdaptiveMode' "$third/probe-metrics.json")" = guarded
test "$(jq 'length' "$third/adaptive-probe-input.json")" -lt 3

jq -n '{fullAudit:true,auditComplete:true,auditCensored:false,at:2000,contextFingerprint:"",schedulerVersion:1,featureContractVersion:1,winnerRecall:0.5,topNRecall:0.5,severeMiss:0.2,eligibleInsufficiencyRate:0,probeSavings:0.3}' >"$TMP/negative.json"
CFIP_ADAPTIVE_NOW=2000 cfip_adaptive_record_audit "$TMP/negative.json"
fourth="$(run_one)"
test "$(jq -r '.effectiveAdaptiveMode' "$fourth/probe-metrics.json")" = shadow
test "$(jq 'length' "$fourth/adaptive-probe-input.json")" = 3

export CFIP_VALIDATE_CANDIDATE_JSON="$(printf '%s' "$CFIP_VALIDATE_CANDIDATE_JSON" | sed 's/"cf_ip.main.adaptive_audit_interval":"2"/"cf_ip.main.adaptive_audit_interval":"1"/')"
TXN_FAIL=true
if run_v2 >/dev/null; then
    echo 'expected transaction failure did not occur' >&2
    exit 1
fi
failed_run="$(ls -td "$CFIP_RUNTIME_DIR"/run-* | head -n1)"
test "$(jq -r '.transactionApplied' "$failed_run/adaptive-audit.json")" = false
test "$(jq -r '.appliedCandidates | length' "$failed_run/adaptive-audit.json")" = 0

echo 'run_v2 Adaptive lifecycle covered Shadow, audit, Guarded subset, fallback downgrade, and final applied evidence'
