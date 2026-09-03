#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_EVIDENCE_MAX_BYTES=1024 CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
jq -cn --argjson reasons "$(jq -cn '[range(0;1000)|"reason"]')" '{decisionId:"byte-cap",effectiveMode:"shadow",nativeOrder:["1.1.1.1"],authorityActionId:"1.1.1.1",confidenceLevel:"medium",confidenceReasons:$reasons}' >"$TMP/decision.json"; printf '%s\n' '{"reward":0.5,"candidateOutcome":"success"}' >"$TMP/outcome.json"
for _ in $(seq 1 20); do cfip_rill_record_evidence "$TMP/decision.json" "$TMP/outcome.json" '{}'; done
test "$(wc -c <"$CFIP_RILL_EVIDENCE_FILE")" -le 1024
echo 'Evidence store enforces a real byte-size bound'
