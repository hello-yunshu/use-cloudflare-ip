#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_RILL_HOLDOUT_INTERVAL=1
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_TARGET_DOMAINS='one.example,two.example'
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

cat >"$TMP/decision.json" <<'JSON'
{"decisionId":"holdout-1","effectiveMode":"assisted","nativeOrder":["104.16.1.1","104.16.1.2"],"authorityActionId":"104.16.1.2"}
JSON
cat >"$TMP/native.json" <<'JSON'
[{"ip":"104.16.1.1","family":"ipv4","lossRate":0.01,"downloadMBps":40}]
JSON
printf '%s\n' '[{"ip":"104.16.1.2"}]' >"$TMP/selected.json"
printf '%s\n' '{"reward":0.8}' >"$TMP/actual.json"
cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:true,connectMs:5,tlsMs:5,ttfbMs:10,totalMs:20}'; }
cfip_rill_holdout "$TMP/decision.json" "$TMP/native.json" "$TMP/actual.json" "$CFIP_TARGET_DOMAINS" 1 "$TMP/holdout.json"
test "$(jq -r '.performed' "$TMP/holdout.json")" = true
test "$(jq -r '.nativeTop1' "$TMP/holdout.json")" = 104.16.1.1
test "$(jq -r '.feedbackEligible' "$TMP/holdout.json")" = false
test "$(jq -c . "$TMP/selected.json")" = '[{"ip":"104.16.1.2"}]'
echo 'Assisted holdout is evaluation-only and preserves production selection'
