#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP/status" CFIP_LOG_FILE="$TMP/operational-history.log" CFIP_OPERATIONAL_STATE_FILE="$TMP/status/operational-health.json" CFIP_OPERATIONAL_HISTORY_FILE="$TMP/status/operational-history.json"
mkdir -p "$CFIP_STATUS_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/operational-health.sh"
export CFIP_MODE=passwall CFIP_ADAPTIVE_MEASUREMENT_MODE=shadow CFIP_ADAPTIVE_EFFECTIVE_MODE=shadow CFIP_RILL_MODE=shadow
jq -n '{schemaVersion:1,qualificationState:"qualified",contextFingerprint:"ctx"}' >"$TMP/adaptive.json"
jq -n '{schemaVersion:1,fullAudit:true,auditComplete:true,auditCensored:false,winnerRecall:1,topNRecall:1,severeMiss:0}' >"$TMP/audit.json"
jq -n '{schemaVersion:1,fullCandidateCount:10,plannedK:5,actualUniqueProbeCount:5,expansionCount:0,fallbackUsed:false,auditRun:true,measurementDurationMs:10,probeDurationMs:5}' >"$TMP/metrics.json"
export CFIP_ADAPTIVE_STATE_FILE="$TMP/adaptive.json" CFIP_ADAPTIVE_AUDIT_FILE="$TMP/audit.json" CFIP_PROBE_METRICS_FILE="$TMP/metrics.json"
for n in 1 2 3 4 5; do
    CFIP_RUN_ID="healthy-$n"; item="$(cfip_operational_record_item true success '')"; cfip_operational_upsert_record "$item"
done
cfip_operational_update healthy baseline
test "$(jq -r '.rolling.meaningful' "$CFIP_OPERATIONAL_STATE_FILE")" = true
test "$(jq -r '.rolling.runFailureRate' "$CFIP_OPERATIONAL_STATE_FILE")" = 0
test "$(jq -r '.state' "$CFIP_OPERATIONAL_STATE_FILE")" = healthy

jq '.fallbackUsed=true | .expansionCount=1' "$TMP/metrics.json" >"$TMP/warning-metrics.json"
export CFIP_PROBE_METRICS_FILE="$TMP/warning-metrics.json"
for n in 1 2 3 4 5; do
    CFIP_RUN_ID="warning-$n"; item="$(cfip_operational_record_item true success '')"; cfip_operational_upsert_record "$item"
done
cfip_operational_update rolling warning
test "$(jq -r '.rolling.fallbackRate' "$CFIP_OPERATIONAL_STATE_FILE")" = 0.5
test "$(jq -r '.state' "$CFIP_OPERATIONAL_STATE_FILE")" = warning

cfip_rill_qualification_json() { printf '%s\n' '{"state":"regressed"}'; }
cfip_operational_update candidate-regression regression
test "$(jq -r '.state' "$CFIP_OPERATIONAL_STATE_FILE")" = degraded
CFIP_ADAPTIVE_MEASUREMENT_MODE=guarded; CFIP_RILL_MODE=assisted; CFIP_REUSE_ENABLED=true
cfip_operational_apply_guardrails
test "$CFIP_ADAPTIVE_MEASUREMENT_MODE" = shadow; test "$CFIP_RILL_MODE" = shadow; test "$CFIP_REUSE_ENABLED" = false

CFIP_RUN_ID=reuse-run; CFIP_REUSE_ATTEMPTED=true; CFIP_REUSE_FALLBACK_REASON=current_validation_failed
cfip_operational_record_event reuse-failure current_validation_failed validation_failure
CFIP_LAST_RESULT=success; cfip_operational_record_run
test "$(jq '[.records[]|select(.runId=="reuse-run")]|length' "$CFIP_OPERATIONAL_HISTORY_FILE")" = 1
test "$(jq -r '.records[]|select(.runId=="reuse-run")|.completed' "$CFIP_OPERATIONAL_HISTORY_FILE")" = true
test "$(jq -r '.records[]|select(.runId=="reuse-run")|.reuseResult' "$CFIP_OPERATIONAL_HISTORY_FILE")" = validation_failure

printf '%s\n' '{broken' >"$CFIP_OPERATIONAL_HISTORY_FILE"
cfip_operational_history_json >/dev/null
test -n "$(find "$CFIP_STATUS_DIR" -name 'operational-history.json.quarantine.*' -print -quit)"
echo 'Operational history bounded/quarantine/rolling/reuse-failure contracts passed'
