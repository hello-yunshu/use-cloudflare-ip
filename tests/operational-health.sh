#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_OPERATIONAL_STATE_FILE="$TMP/operational-health.json" CFIP_ADAPTIVE_MEASUREMENT_MODE=guarded CFIP_RILL_MODE=assisted CFIP_REUSE_ENABLED=true
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/context-policy.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/operational-health.sh"

test "$(jq -r '.state' < <(cfip_operational_state_json))" = healthy
jq -n '{schemaVersion:1,qualificationState:"stale",qualificationReason:"evidence_stale",freshAt:0}' | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
cfip_operational_update adaptive-fallback insufficient_fresh_evidence
test "$(jq -r '.state' "$CFIP_OPERATIONAL_STATE_FILE")" = warning
CFIP_OPERATIONAL_GUARDRAIL_APPLIED=false
cfip_operational_apply_guardrails
test "$CFIP_ADAPTIVE_AUDIT_INTERVAL" = 10

jq -n '{schemaVersion:1,qualificationState:"insufficient",qualificationReason:"negative_evidence",freshAt:0}' | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
cfip_operational_update run-failed adaptive_regression
test "$(jq -r '.state' "$CFIP_OPERATIONAL_STATE_FILE")" = degraded
cfip_operational_apply_guardrails
test "$CFIP_ADAPTIVE_MEASUREMENT_MODE" = shadow
test "$CFIP_RILL_MODE" = shadow
test "$CFIP_REUSE_ENABLED" = false
test "$(cfip_context_policy_id)" = conservative-default
echo 'Operational health warning/degraded states and conservative downgrade guardrails passed'
