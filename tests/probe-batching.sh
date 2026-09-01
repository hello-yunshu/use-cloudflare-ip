#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
cat >"$TMP/input.json" <<'JSON'
[{"ip":"1.1.1.1","family":"ipv4","cfstRank":1},{"ip":"1.1.1.2","family":"ipv4","cfstRank":2},{"ip":"1.1.1.3","family":"ipv4","cfstRank":10},{"ip":"1.1.1.4","family":"ipv4","cfstRank":11},{"ip":"1.1.1.5","family":"ipv4","cfstRank":12}]
JSON
cfip_probe_one() {
  local ip="$1" domain="$2" family="$3"
  if [[ "$ip" == 1.1.1.1 ]]; then jq -cn --arg ip "$ip" --arg domain "$domain" --arg family "$family" '{ip:$ip,domain:$domain,family:$family,success:true,totalMs:40,ttfbMs:20,connectMs:10,tlsMs:10}'; else jq -cn --arg ip "$ip" --arg domain "$domain" --arg family "$family" '{ip:$ip,domain:$domain,family:$family,success:false,totalMs:0,ttfbMs:0,connectMs:0,tlsMs:0}'; fi
}
export CFIP_EARLY_STOP_ENABLED=true CFIP_PROBE_CONCURRENCY=2 CFIP_PROBE_METRICS_FILE="$TMP/metrics.json"
cfip_probe_candidates_batched "$TMP/input.json" "$TMP/output.json" one.example 1 1 2 5
test "$(jq -r 'length' "$TMP/output.json")" = 2
test "$(jq -r '.candidatesConsidered' "$TMP/metrics.json")" = 5
test "$(jq -r '.candidatesProbed' "$TMP/metrics.json")" = 2
test "$(jq -r '.avoidedProbes' "$TMP/metrics.json")" = 3
test "$(jq -r '.earlyStopHit' "$TMP/metrics.json")" = true
echo 'Batched probe and deterministic early-stop contract passed'
