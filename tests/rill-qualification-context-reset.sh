#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_HISTORY_FILE="$TMP/history.json" CFIP_RILL_PREFIX_HISTORY_FILE="$TMP/prefix.json" CFIP_RILL_COLO_HISTORY_FILE="$TMP/colo.json" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cfip_rill_context_guard; old="$(cfip_rill_context_fingerprint)"
for file in "$CFIP_RILL_STATE" "$CFIP_RILL_QUALIFICATION_FILE" "$CFIP_RILL_HISTORY_FILE" "$CFIP_RILL_PREFIX_HISTORY_FILE" "$CFIP_RILL_COLO_HISTORY_FILE" "$CFIP_RILL_EVIDENCE_FILE"; do printf '%s\n' '{}' >"$file"; done
CFIP_TARGET_DOMAINS=two.example; cfip_rill_context_guard
test "$(jq -r '.contextChanged' "$CFIP_RILL_STATE_META_FILE")" = true
test "$(jq -r '.previousContextFingerprint' "$CFIP_RILL_STATE_META_FILE")" = "$old"
test "$(find "$TMP" -name '*.quarantine.context.*' -type f | wc -l | tr -d ' ')" = 6
echo 'Context change resets every Candidate-dependent evidence lineage'
