#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export CFIP_STATUS_DIR="$tmp" CFIP_IP_COUNT=1 CFIP_ADAPTIVE_CONTEXT_FINGERPRINT=ctx CFIP_ADAPTIVE_NOW=1000 CFIP_ADAPTIVE_MEASUREMENT_ENABLED=true CFIP_ADAPTIVE_MEASUREMENT_MODE=guarded
export CFIP_ADAPTIVE_SCHEDULER_VERSION=1 CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION=1 CFIP_ADAPTIVE_MIN_EVIDENCE=2 CFIP_ADAPTIVE_EVIDENCE_WINDOW=3 CFIP_ADAPTIVE_EVALUATION_MAX_AGE_SECONDS=100
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"

jq -n '{candidateCount:2,selectedK:1,selectedIps:["192.0.2.1"],adaptiveOrder:["192.0.2.1","192.0.2.2"],baselineOrder:["192.0.2.1","192.0.2.2"],cfstOrder:["192.0.2.1","192.0.2.2"],candidates:[{ip:"192.0.2.1"},{ip:"192.0.2.2"}]}' >"$tmp/plan.json"
jq -n '[{ip:"192.0.2.1",eligible:true,probes:[{errorClass:"none"}],probeSummary:{probeCount:1,successCount:1,totalMs:10,ttfbMs:5},lossRate:0},{ip:"192.0.2.2",eligible:true,probes:[{errorClass:"none"}],probeSummary:{probeCount:1,successCount:1,totalMs:20,ttfbMs:5},lossRate:0}]' >"$tmp/full.json"
jq -n '[{ip:"192.0.2.1",nativeRank:1},{ip:"192.0.2.2",nativeRank:2}]' >"$tmp/native.json"
for seq in 1 2; do
    CFIP_RUN_ID="full-$seq" CFIP_ADAPTIVE_NOW="$((1000+seq))" cfip_adaptive_make_audit_record "$tmp/plan.json" "$tmp/native.json" "$tmp/full.json" "$tmp/audit.json"
    cfip_adaptive_record_audit "$tmp/audit.json"
done
test "$(jq -r '.qualificationState' "$CFIP_ADAPTIVE_STATE_FILE")" = qualified
test "$(CFIP_ADAPTIVE_NOW=1002 cfip_adaptive_effective_mode)" = guarded
rm -f "$tmp/full.json"
cfip_adaptive_make_audit_record "$tmp/plan.json" "$tmp/native.json" "$tmp/full.json" "$tmp/censored.json" 1
test "$(jq -r '.auditComplete' "$tmp/censored.json")" = false
test "$(jq -r '.auditCensored' "$tmp/censored.json")" = true
! cfip_adaptive_record_audit "$tmp/censored.json"
jq -n '{fullAudit:true,auditComplete:true,auditCensored:false,contextFingerprint:"ctx",schedulerVersion:1,featureContractVersion:1,winnerRecall:0.5,topNRecall:0.5,severeMiss:0.2,eligibleInsufficiencyRate:0,probeSavings:0.3}' >"$tmp/negative.json"
cfip_adaptive_record_audit "$tmp/negative.json"
test "$(jq -r '.qualificationState' "$CFIP_ADAPTIVE_STATE_FILE")" = insufficient
test "$(CFIP_ADAPTIVE_NOW=1002 cfip_adaptive_effective_mode)" = shadow
test "$(grep -c 'cfip_probe_candidates \"\$CFIP_PROBE_INPUT_FILE\"' "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2")" = 1
echo 'Adaptive lifecycle qualifies, downgrades on negative evidence, and audits one full production run'
