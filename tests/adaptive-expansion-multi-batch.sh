#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export CFIP_STATUS_DIR="$tmp" CFIP_IP_COUNT=2 CFIP_IP_TYPE=ipv4
export CFIP_ADAPTIVE_MEASUREMENT_ENABLED=true CFIP_ADAPTIVE_MEASUREMENT_MODE=guarded
export CFIP_ADAPTIVE_MAX_PROBE_COUNT=4 CFIP_ADAPTIVE_EXPANSION_BATCH_SIZE=1
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"

jq -n '[range(1;6)|{ip:("192.0.2." + tostring),family:"ipv4",cfstRank:.}]' >"$tmp/input.json"
jq -n --slurpfile candidates "$tmp/input.json" '$candidates[0] | {candidateCount:5,selectedK:1,selectedIps:["192.0.2.1"],candidates:.,remainingCandidates:[{ip:"192.0.2.2",family:"ipv4"},{ip:"192.0.2.3",family:"ipv4"},{ip:"192.0.2.4",family:"ipv4"},{ip:"192.0.2.5",family:"ipv4"}]}' >"$tmp/plan.json"
cfip_probe_candidates() {
    local input="$1" output="$2" call
    call=$(( $(wc -l <"$tmp/probed.log" 2>/dev/null || printf 0) + 1 ))
    jq -c . "$input" >"$tmp/batch-$call.json"
    jq -r '.[].ip' "$tmp/batch-$call.json" >>"$tmp/probed.log"
    jq --argjson call "$call" '.[]|. + {eligible:($call >= 3),lossRate:(if $call >= 3 then 0 else 1 end),probeSummary:{totalMs:(if $call >= 3 then 10 else 9000 end),ttfbMs:(if $call >= 3 then 5 else 9000 end)}}' "$tmp/batch-$call.json" | jq -s . >"$output"
}
cfip_adaptive_probe "$tmp/input.json" "$tmp/output.json" example.test 1 2 1 4 "$tmp/plan.json" "$tmp/metrics.json" guarded
test "$(sort "$tmp/probed.log" | uniq -d | wc -l | tr -d ' ')" = 0
test "$(wc -l <"$tmp/probed.log" | tr -d ' ')" = 4
test "$(jq 'length' "$tmp/output.json")" = 4
test "$(jq '[.[].ip]|unique|length' "$tmp/output.json")" = 4
test "$(jq -r '.expansionCount' "$tmp/metrics.json")" = 3
echo 'Adaptive expansion advances through three unique batches'
