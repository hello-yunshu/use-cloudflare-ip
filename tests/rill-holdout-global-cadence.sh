#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_RILL_HOLDOUT_INTERVAL=5 CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
for n in $(seq 1 4); do jq -cn --arg id "decision-$n" '{decisionId:$id,effectiveMode:"assisted",nativeOrder:["E"],authorityActionId:"R"}' >"$TMP/decision.json"; if cfip_rill_holdout_due "$TMP/decision.json"; then exit 1; fi; done
jq -cn '{decisionId:"decision-5",effectiveMode:"assisted",nativeOrder:["E"],authorityActionId:"R"}' >"$TMP/decision.json"
cfip_rill_holdout_due "$TMP/decision.json"
echo 'Assisted holdout cadence is global within the current context and lineage'
