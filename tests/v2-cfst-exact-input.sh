#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log" CFIP_IP_TYPE=both CFIP_CANDIDATE_BUDGET=100
mkdir -p "$TMP/work/cfst"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
cat >"$TMP/records.json" <<'JSON'
[
 {"kind":"ip","value":"104.17.1.1","family":"ipv4","sourceId":"community","sourceClass":"community","stale":false},
 {"kind":"cidr","value":"104.16.0.0/13","family":"ipv4","sourceId":"official","sourceClass":"official","stale":false},
 {"kind":"cidr","value":"2606:4700::/32","family":"ipv6","sourceId":"official-v6","sourceClass":"official","stale":false}
]
JSON
printf '[]\n' >"$TMP/history.json"
cfip_schedule_family ipv4 100 "$TMP/records.json" "$TMP/history.json" "$TMP/scheduled.json"
jq -e 'length==100 and any(.[]; .ip=="104.17.1.1") and all(.[]; (.ip|contains("/"))|not)' "$TMP/scheduled.json" >/dev/null
! jq -r '.[].ip' "$TMP/scheduled.json" | grep -Fx '104.16.0.0/24'
cfip_collect_enabled_sources() { cp "$TMP/records.json" "$1"; printf '[]\n' >"$2"; }
cfip_history_pool_json() { cp "$TMP/history.json" "$1"; }
cfip_prepare_candidate_pool "$TMP/pool.json" "$TMP/input.txt" "$TMP/source-status.json"
test "$(grep -Fx '104.17.1.1/32' "$TMP/input.txt" | wc -l | tr -d ' ')" -eq 1
! grep -Eq '/(8|16|24)$' "$TMP/input.txt"
echo 'v2 exact concrete CFST input contract passed'
