#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFIP_RUN_ID=test-run; CFIP_LOG_FILE="$TMP/test.log"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
cfip_parse_cfst "$TMP/candidates.json" tcp 32 "$ROOT/tests/fixtures/cfst/tcp-normal.csv:ipv4"
test "$(jq 'length' "$TMP/candidates.json")" -eq 2
test "$(jq -r '.[1].lossRate' "$TMP/candidates.json")" = 0.25
test "$(jq -r '.[0].avgLatencyMs' "$TMP/candidates.json")" = 35.2
cfip_parse_cfst "$TMP/malformed.json" tcp 32 "$ROOT/tests/fixtures/cfst/malformed.csv:ipv4"
test "$(jq 'length' "$TMP/malformed.json")" -eq 1
jq -e '.[0].lossRate==null and .[0].avgLatencyMs==null and .[0].downloadMBps==null' "$TMP/malformed.json" >/dev/null
cfip_probe_one(){ local ip="$1" domain="$2" family="$3"; if [[ "$ip" == 104.16.1.1 ]]; then jq -cn --arg ip "$ip" --arg d "$domain" --arg f "$family" '{ip:$ip,domain:$d,family:$f,success:true,connectMs:20,tlsMs:30,ttfbMs:40,totalMs:50}'; else jq -cn --arg ip "$ip" --arg d "$domain" --arg f "$family" '{ip:$ip,domain:$d,family:$f,success:false,connectMs:0,tlsMs:0,ttfbMs:0,totalMs:0}'; fi; }
cfip_probe_candidates "$TMP/candidates.json" "$TMP/probed.json" example.com 3
cfip_native_rank "$TMP/probed.json" "$TMP/native.json"
test "$(jq 'length' "$TMP/native.json")" -eq 1
test "$(jq -r '.[0].ip' "$TMP/native.json")" = 104.16.1.1
jq '.[0:4]' "$TMP/native.json" >"$TMP/selected.json"; test "$(jq 'length' "$TMP/selected.json")" -eq 1

# Post-apply verification must cover every unique applied IP, not just selected[0].
cfip_probe_one(){ local ip="$1" domain="$2" family="$3"; jq -cn --arg ip "$ip" --arg d "$domain" --arg f "$family" '{ip:$ip,domain:$d,family:$f,success:true,connectMs:10,tlsMs:20,ttfbMs:30,totalMs:40}'; }
CFIP_RUN_ID=post-apply-test; printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"},{"ip":"104.16.1.2","family":"ipv4"}]' >"$TMP/post-selected.json"; cfip_post_apply_probe "$TMP/post-selected.json" example.com 3 "$TMP/post.json"
jq -e '.validated==true and (.appliedIps|length)==2 and (.probes|length)==2' "$TMP/post.json" >/dev/null
echo 'v2 observation/eligibility tests passed'
