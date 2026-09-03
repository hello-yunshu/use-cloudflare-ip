#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
export CFIP_RILL_PREFIX_HISTORY_FILE="$TMP/prefix-history.json" CFIP_RILL_COLO_HISTORY_FILE="$TMP/colo-history.json" CFIP_RILL_HISTORY_FILE="$TMP/history.json"
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
now="$(date +%s)"
printf '%s\n' "{\"104.16.1.0/24\":{\"samples\":8,\"successRate\":0.5,\"consecutiveFailures\":3,\"lastSeen\":$((now-604800))}}" >"$CFIP_RILL_PREFIX_HISTORY_FILE"
printf '%s\n' '{"entries":{}}' >"$CFIP_RILL_COLO_HISTORY_FILE"
printf '%s\n' '[]' >"$CFIP_RILL_HISTORY_FILE"
printf '%s\n' '[{"ip":"104.16.1.9","family":"ipv4","cfstRank":1,"prefixKey":"104.16.1.0/24"}]' >"$TMP/input.json"
cfip_rill_probe_priority "$TMP/input.json" "$TMP/output.json"
jq -e '.[0].prefixHistoryScore == 0.5' "$TMP/output.json" >/dev/null
cfip_rill_actions_json "$TMP/input.json" >"$TMP/actions.json"
jq -e '.[0].features[21] == 0.5' "$TMP/actions.json" >/dev/null
echo 'Prefix failure penalty decay contract passed'
