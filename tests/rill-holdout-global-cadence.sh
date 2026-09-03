#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_RILL_HOLDOUT_INTERVAL=5 CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
fp="$(cfip_rill_context_fingerprint)"; lineage="$(cfip_rill_lineage_id)"; jq -cn --arg fp "$fp" --arg lineage "$lineage" '["A","B","C","D"] | to_entries | map({effectiveMode:"assisted",contextFingerprint:$fp,stateLineage:$lineage,nativeTop1:(.value),authorityActionId:"R",holdoutPerformed:false})' >"$CFIP_RILL_EVIDENCE_FILE"
jq -cn '{decisionId:"cadence",effectiveMode:"assisted",nativeOrder:["E"],authorityActionId:"R"}' >"$TMP/decision.json"
cfip_rill_holdout_due "$TMP/decision.json"
echo 'Assisted holdout cadence is global within the current context and lineage'
