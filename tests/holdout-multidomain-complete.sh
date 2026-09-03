#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_HOLDOUT_INTERVAL=1 CFIP_RILL_HOLDOUT_STATE_FILE="$TMP/cadence.json"
export CFIP_TARGET_DOMAINS='one.example,two.example' CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

printf '%s\n' '{"decisionId":"multi-complete","effectiveMode":"assisted","nativeOrder":["1.1.1.1"],"authorityActionId":"2.2.2.2"}' >"$TMP/decision.json"
printf '%s\n' '[{"ip":"1.1.1.1","family":"ipv4"}]' >"$TMP/native.json"
printf '%s\n' '{"reward":0.8}' >"$TMP/actual.json"
cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:true,errorClass:"none",connectMs:10,tlsMs:10,ttfbMs:20,totalMs:40}'; }
cfip_rill_holdout "$TMP/decision.json" "$TMP/native.json" "$TMP/actual.json" "$CFIP_TARGET_DOMAINS" 1 "$TMP/complete.json"
test "$(jq -r '.performed' "$TMP/complete.json")" = true
test "$(jq '.nativeTop1' "$TMP/complete.json")" = '"1.1.1.1"'

rm -f "$TMP/cadence.json"
cfip_probe_one() { [[ "$2" == two.example ]] && return 1; jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:true,errorClass:"none",connectMs:10,tlsMs:10,ttfbMs:20,totalMs:40}'; }
cfip_rill_holdout "$TMP/decision.json" "$TMP/native.json" "$TMP/actual.json" "$CFIP_TARGET_DOMAINS" 1 "$TMP/unavailable.json"
test "$(jq -r '.performed' "$TMP/unavailable.json")" = false
test "$(jq -r '.comparison' "$TMP/unavailable.json")" = unavailable
echo 'Holdout comparison requires a complete record for every target domain'
