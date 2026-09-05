#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/status" "$TMP/runtime" "$TMP/run"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log" CFIP_LEGACY_BIN=/bin/false
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
CFIP_RUN_ID=history-fixture; CFIP_LAST_RESULT=success; CFIP_MODE=passwall; CFIP_IP_COUNT=1; CFIP_RILL_MODE=shadow; CFIP_ADAPTIVE_MEASUREMENT_MODE=shadow; CFIP_ADAPTIVE_EFFECTIVE_MODE=shadow
CFIP_SELECTED_FILE="$TMP/run/selected.json"; CFIP_PROBE_METRICS_FILE="$TMP/run/metrics.json"; CFIP_ADAPTIVE_STATE_FILE="$TMP/status/adaptive.json"; CFIP_DECISION_FILE="$TMP/run/decision.json"; CFIP_TXN_RESULT_FILE="$TMP/run/transaction.json"; CFIP_ADAPTIVE_AUDIT_FILE="$TMP/run/audit.json"
printf '%s\n' '[{"ip":"1.1.1.1"}]' >"$CFIP_SELECTED_FILE"
printf '%s\n' '{"fullCandidateCount":10,"plannedK":4,"actualUniqueProbeCount":4,"fallbackUsed":false,"expansionCount":0,"measurementDurationMs":123,"probeDurationMs":45,"auditRun":false,"effectiveAdaptiveMode":"shadow"}' >"$CFIP_PROBE_METRICS_FILE"
printf '%s\n' '{"qualificationState":"qualified"}' >"$CFIP_ADAPTIVE_STATE_FILE"
printf '%s\n' '{"effectiveMode":"shadow"}' >"$CFIP_DECISION_FILE"
printf '%s\n' '{"success":true}' >"$CFIP_TXN_RESULT_FILE"
remember_history
row="$(tail -n1 "$CFIP_RUN_HISTORY")"
jq -e '(.mode=="passwall") and (.proxyMode=="passwall") and (.adaptiveMode=="shadow") and (.candidateMode=="shadow") and (.fullCandidateCount==10) and (.plannedK==4) and (.actualUniqueProbeCount==4) and (.measurementDurationMs==123) and (.transactionApplied==true) and (.bestIps==["1.1.1.1"])' <<<"$row" >/dev/null
! jq -e '.adaptiveMode=="passwall" or .candidateMode=="passwall"' <<<"$row" >/dev/null
echo 'Recent run history additive field and mode separation contract passed'
