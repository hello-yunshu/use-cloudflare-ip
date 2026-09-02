#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
export CFIP_RILL_PREFIX_HISTORY_FILE="$TMP/prefix-history.json" CFIP_RILL_COLO_HISTORY_FILE="$TMP/colo-history.json"
export CFIP_RILL_HISTORY_FILE="$TMP/candidate-history.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

test "$(cfip_prefix_key 104.16.1.9)" = '104.16.1.0/24'
test "$(cfip_prefix_key 2606:4700::1)" = '2606:4700:0000:0000/64'
test "$(cfip_prefix_key 2606:4700:0:0::2)" = '2606:4700:0000:0000/64'

cat >"$TMP/observations.json" <<'JSON'
[
  {"ip":"104.16.1.9","prefixKey":"104.16.1.0/24","colo":"HKG","eligible":true,"lossRate":0,"downloadMBps":80,"probeSummary":{"totalMs":100,"ttfbMs":20}},
  {"ip":"104.16.1.10","prefixKey":"104.16.1.0/24","colo":"HKG","eligible":false,"lossRate":1,"downloadMBps":0,"probeSummary":{"totalMs":9000,"ttfbMs":4000}},
  {"ip":"104.17.1.9","prefixKey":"104.17.1.0/24","colo":"LAX","eligible":true,"lossRate":0,"downloadMBps":70,"probeSummary":{"totalMs":120,"ttfbMs":25}},
  {"ip":"2606:4700:0000:0000::1","prefixKey":"2606:4700:0000:0000/64","colo":null,"eligible":true,"lossRate":0,"downloadMBps":60,"probeSummary":{"totalMs":150,"ttfbMs":30}}
]
JSON
cfip_rill_update_prefix_history "$TMP/observations.json"
cfip_rill_update_colo_history "$TMP/observations.json"
jq -e '.["104.16.1.0/24"].samples == 2 and .["104.16.1.0/24"].failures == 1 and .["104.17.1.0/24"].samples == 1' "$CFIP_RILL_PREFIX_HISTORY_FILE" >/dev/null
jq -e '.entries.HKG.samples == 2 and .entries.LAX.samples == 1 and .unknownCount == 1 and .entries.HKG.successRate == 0.5' "$CFIP_RILL_COLO_HISTORY_FILE" >/dev/null

cat >"$TMP/candidates.json" <<'JSON'
[{"ip":"104.17.1.9","prefixKey":"104.17.1.0/24","family":"ipv4","avgLatencyMs":100,"downloadMBps":80,"lossRate":0,"probeSummary":{"connectMs":10,"tlsMs":10,"ttfbMs":20,"totalMs":100},"cfstRank":1,"sourceCount":1,"sources":["official"],"sourceStale":false}]
JSON
actions="$(cfip_rill_actions_json "$TMP/candidates.json")"
test "$(jq -r '.[0].features | length' <<<"$actions")" = 22
test "$(jq -r '.[0].features[21] > 0.5' <<<"$actions")" = true
echo 'Prefix aggregate, IPv6 normalization and Colo intelligence passed'
