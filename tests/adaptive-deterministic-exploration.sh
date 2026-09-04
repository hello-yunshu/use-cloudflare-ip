#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export CFIP_STATUS_DIR="$tmp" CFIP_IP_COUNT=1 CFIP_IP_TYPE=ipv4 CFIP_ADAPTIVE_MEASUREMENT_ENABLED=true CFIP_ADAPTIVE_MEASUREMENT_MODE=shadow
export CFIP_ADAPTIVE_MIN_PROBE_COUNT=1 CFIP_ADAPTIVE_MAX_PROBE_COUNT=2 CFIP_ADAPTIVE_TARGET_RATIO_PERCENT=25 CFIP_ADAPTIVE_EXPLORATION_RATIO_PERCENT=100
export CFIP_ADAPTIVE_CONTEXT_FINGERPRINT=ctx
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
jq -n '[range(1;9)|{ip:("192.0.2."+tostring),family:"ipv4",cfstRank:(.+1),sourceReliability:0.5}]' >"$tmp/input.json"
CFIP_ADAPTIVE_RUN_SEQUENCE=1 cfip_adaptive_write_plan "$tmp/input.json" "$tmp/one.json"
CFIP_ADAPTIVE_RUN_SEQUENCE=1 cfip_adaptive_write_plan "$tmp/input.json" "$tmp/two.json"
cmp "$tmp/one.json" "$tmp/two.json"
CFIP_ADAPTIVE_RUN_SEQUENCE=2 cfip_adaptive_write_plan "$tmp/input.json" "$tmp/three.json"
test "$(jq -c '.explorationIps' "$tmp/one.json")" = "$(jq -c '.explorationIps' "$tmp/two.json")"
test "$(jq -c '.explorationIps' "$tmp/one.json")" != "$(jq -c '.explorationIps' "$tmp/three.json")"
echo 'Adaptive exploration is deterministic per run and rotates across runs'
