#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_LOG_FILE="$TMP/log" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_PENDING_FILE="$TMP/pending.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_TARGET_DOMAINS='one.example' CFIP_SPEEDTEST_PROTOCOL=tcp CFIP_IP_TYPE=ipv4 CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cfip_rill_context_guard; old="$(cfip_rill_context_fingerprint)"
jq -cn --arg fp "$old" '[{dueAt:0,expiresAt:9999999999,decision:{decisionId:"old",selectedActionId:"1.1.1.1",generation:1},outcome:{candidateOutcome:"success",hostOutcome:"success",observedIp:"1.1.1.1"},partitionKey:"candidate",contextFingerprint:$fp,modelGeneration:2,featureSchemaHash:"old"}]' > "$CFIP_RILL_PENDING_FILE"
CFIP_TARGET_DOMAINS='two.example'; cfip_rill_context_guard; test "$(jq -r '.[0].rejectedReason' "$CFIP_RILL_PENDING_FILE")" = context_changed
cfip_rill_process_pending_feedback; test "$(jq -r 'length' "$CFIP_RILL_PENDING_FILE")" = 0; test "$(jq -r '.delayedRejected' "$CFIP_RILL_QUALIFICATION_FILE")" = 1
echo 'Pending delayed feedback is isolated and rejected after context change'
