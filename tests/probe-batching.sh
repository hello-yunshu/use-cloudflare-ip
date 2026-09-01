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
cfip_probe_candidate_record() {
  local candidate="$1" domain_csv="$2" _timeout="$3" output="$4"
  local ok=false
  [[ "$(jq -r '.ip' <<<"$candidate")" == 1.1.1.1 ]] && ok=true
  jq -cn --argjson candidate "$candidate" --argjson ok "$ok" \
    '$candidate + {eligible:$ok,probes:[{success:$ok,totalMs:(if $ok then 40 else 0 end),ttfbMs:(if $ok then 20 else 0 end)}],probeSummary:{totalMs:(if $ok then 40 else 0 end),ttfbMs:(if $ok then 20 else 0 end),lossRate:(if $ok then 0 else 1 end)}}' >"$output"
}
export CFIP_EARLY_STOP_ENABLED=true CFIP_PROBE_CONCURRENCY=2 CFIP_PROBE_METRICS_FILE="$TMP/metrics.json"
cfip_probe_candidates_batched "$TMP/input.json" "$TMP/output.json" one.example 1 1 2 5
test "$(jq -r 'length' "$TMP/output.json")" = 2
test "$(jq -r '.candidatesConsidered' "$TMP/metrics.json")" = 5
test "$(jq -r '.candidatesProbed' "$TMP/metrics.json")" = 2
test "$(jq -r '.avoidedProbes' "$TMP/metrics.json")" = 3
test "$(jq -r '.earlyStopHit' "$TMP/metrics.json")" = true
echo 'Batched probe and deterministic early-stop contract passed'
