#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
export CFIP_RILL_STATE="$TMP/rill-state.json" CFIP_RILL_STATE_META_FILE="$TMP/rill-state-meta.json"
export CFIP_RILL_SCHEMA_FILE="$ROOT/contracts/rill-runtime.json" CFIP_SOURCE_POLICY_QUALIFICATION_FILE="$TMP/source-policy-qualification.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
printf '%s\n' '{"state":"shadow-qualified","stateGeneration":4,"stateLineage":"old-lineage"}' >"$CFIP_SOURCE_POLICY_QUALIFICATION_FILE"
printf '%s\n' '{"lineageId":"old-lineage","resetRequired":false}' >"$CFIP_RILL_STATE_META_FILE"
cfip_rill_rotate_lineage manual_reset
test ! -e "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE"
jq -e '.lineageId != "old-lineage" and .resetReason == "manual_reset"' "$CFIP_RILL_STATE_META_FILE" >/dev/null
echo 'Source policy qualification reset lineage contract passed'
