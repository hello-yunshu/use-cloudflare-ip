#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export CFIP_STATUS_DIR="$tmp" CFIP_ADAPTIVE_CONTEXT_FINGERPRINT=ctx CFIP_ADAPTIVE_NOW=1000 CFIP_RUN_ID=multi-ip
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
jq -n '{candidateCount:8,selectedK:4,selectedIps:["192.0.2.1","192.0.2.2","192.0.2.3","192.0.2.4"],adaptiveOrder:["192.0.2.1","192.0.2.2","192.0.2.3","192.0.2.4","192.0.2.5","192.0.2.6","192.0.2.7","192.0.2.8"],baselineOrder:["192.0.2.1"],cfstOrder:["192.0.2.1"],candidates:[range(1;9)|{ip:("192.0.2."+tostring)}]}' >"$tmp/plan.json"
jq -n '[range(1;9)|{ip:("192.0.2."+tostring),eligible:true,probes:[{errorClass:"none"}],probeSummary:{probeCount:1,successCount:1,totalMs:10,ttfbMs:5},lossRate:0}]' >"$tmp/full.json"
# Native ranking is intentionally supplied in the expected order for this contract test.
jq -n '[range(1;9)|{ip:("192.0.2."+tostring),nativeRank:(.+1)}]' >"$tmp/native.json"
for count in 1 4 6; do
    export CFIP_IP_COUNT="$count"
    cfip_adaptive_make_audit_record "$tmp/plan.json" "$tmp/native.json" "$tmp/full.json" "$tmp/audit-$count.json"
    test "$(jq '(.fullNativeTopN|length)' "$tmp/audit-$count.json")" = "$count"
    test "$(jq -r '.auditComplete' "$tmp/audit-$count.json")" = true
done
echo 'Adaptive qualification Top-N follows IP_COUNT for 1, 4, and 6'
