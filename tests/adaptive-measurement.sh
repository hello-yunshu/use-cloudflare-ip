#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export CFIP_STATUS_DIR="$tmp"
export CFIP_IP_COUNT=2 CFIP_IP_TYPE=both
export CFIP_ADAPTIVE_MEASUREMENT_ENABLED=true CFIP_ADAPTIVE_MEASUREMENT_MODE=shadow
export CFIP_ADAPTIVE_TARGET_RATIO_PERCENT=25 CFIP_ADAPTIVE_MIN_PROBE_COUNT=2
export CFIP_ADAPTIVE_MAX_PROBE_COUNT=4 CFIP_ADAPTIVE_EXPANSION_BATCH_SIZE=2
export CFIP_ADAPTIVE_MIN_EVIDENCE=3 CFIP_ADAPTIVE_EVIDENCE_WINDOW=5
export CFIP_ADAPTIVE_EVALUATION_MAX_AGE_SECONDS=100
export CFIP_ADAPTIVE_NOW=1000 CFIP_ADAPTIVE_CONTEXT_FINGERPRINT=ctx
export CFIP_RUN_ID=adaptive-test

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"

cat >"$tmp/input.json" <<'EOF_INPUT'
[
  {"ip":"2.2.2.2","family":"ipv4","cfstRank":2,"sourceCount":1,"sourceReliability":0.6,"historyEWMA":30},
  {"ip":"2606:4700::1","family":"ipv6","cfstRank":3,"sourceCount":2,"sourceReliability":0.8},
  {"ip":"1.1.1.1","family":"ipv4","cfstRank":1,"sourceCount":1,"sourceReliability":0.4,"previousWinner":true},
  {"ip":"2606:4700::2","family":"ipv6","cfstRank":4,"sourceStale":true,"probes":[{"totalMs":1}]}
]
EOF_INPUT

orders="$(cfip_adaptive_orders_json "$tmp/input.json")"
test "$(jq -r '.baselineOrder|join(",")' <<<"$orders")" = "2.2.2.2,2606:4700::1,1.1.1.1,2606:4700::2"
test "$(jq -r '.adaptiveOrder|length' <<<"$orders")" = 4
test "$(jq -e '.candidates|all(has("probes")|not)' <<<"$orders")" = true
test "$(cfip_adaptive_contract_json | jq -r '.forbiddenFields|index("probes")')" = 0

cp "$tmp/input.json" "$tmp/baseline.json"
cfip_adaptive_prepare_probe_input "$tmp/input.json" "$tmp/shadow.json" "$tmp/plan.json"
cmp "$tmp/input.json" "$tmp/shadow.json"
test "$(cfip_adaptive_effective_mode)" = shadow

export CFIP_ADAPTIVE_MEASUREMENT_MODE=guarded
jq -cn '{schemaVersion:1,qualificationState:"qualified",freshAt:1000,contextFingerprint:"ctx",schedulerVersion:1,featureContractVersion:1}' | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
cfip_adaptive_prepare_probe_input "$tmp/input.json" "$tmp/guarded.json" "$tmp/guarded-plan.json"
test "$(jq 'length' "$tmp/guarded.json")" = 2
test "$(jq -r '[.[].family]|sort|join(",")' "$tmp/guarded.json")" = "ipv4,ipv6"
test "$(jq -r '.selectedIps|index("1.1.1.1")' "$tmp/guarded-plan.json")" = 0
test "$(jq -r '.selectedIps|index("2606:4700::1")' "$tmp/guarded-plan.json")" = 1

cfip_probe_candidates() {
    jq '.[] | . + {eligible:true,lossRate:0,probeSummary:{totalMs:10,ttfbMs:5}}' "$1" | jq -s . >"$2"
}
cfip_adaptive_probe "$tmp/input.json" "$tmp/probed.json" example.test 1 2 2 4 "$tmp/guarded-plan.json" "$tmp/metrics.json" guarded
test "$(jq 'length' "$tmp/probed.json")" = 2
test "$(jq -r '.adaptiveFallback' "$tmp/metrics.json")" = false

cfip_probe_candidates() {
    if [[ ! -e "$tmp/expanded-first" ]]; then
        : >"$tmp/expanded-first"
        jq '.[] | . + {eligible:false,lossRate:1,probeSummary:{totalMs:9000,ttfbMs:9000}}' "$1" | jq -s . >"$2"
    else
        jq '.[] | . + {eligible:true,lossRate:0,probeSummary:{totalMs:10,ttfbMs:5}}' "$1" | jq -s . >"$2"
    fi
}
cfip_probe_candidates_batched() {
    jq '.[] | . + {eligible:true,lossRate:0,probeSummary:{totalMs:10,ttfbMs:5}}' "$1" | jq -s . >"$2"
}
cfip_adaptive_probe "$tmp/input.json" "$tmp/expanded.json" example.test 1 2 2 4 "$tmp/guarded-plan.json" "$tmp/expanded-metrics.json" guarded
test "$(jq -r '.adaptiveFallback' "$tmp/expanded-metrics.json")" = false
test "$(jq -r '.adaptiveProbed' "$tmp/expanded-metrics.json")" = 4
test "$(jq -r '.lastExpansionCount' "$CFIP_ADAPTIVE_STATE_FILE")" = 1

cfip_probe_candidates() { return 1; }
cfip_adaptive_probe "$tmp/input.json" "$tmp/fallback.json" example.test 1 2 2 4 "$tmp/guarded-plan.json" "$tmp/fallback-metrics.json" guarded
test "$(jq -r '.adaptiveFallback' "$tmp/fallback-metrics.json")" = true
test "$(jq 'length' "$tmp/fallback.json")" = 4

CFIP_ADAPTIVE_AUDIT_INTERVAL=2
jq -n '{schemaVersion:1,runCount:0,lastContextFingerprint:"ctx",qualificationState:"insufficient",schedulerVersion:1,featureContractVersion:1}' | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
CFIP_RUN_ID=cadence-1; if cfip_adaptive_note_run; then exit 1; fi
CFIP_RUN_ID=cadence-2; cfip_adaptive_note_run
test "$(jq -r '.runCount' "$CFIP_ADAPTIVE_STATE_FILE")" = 2

jq -n '[range(0;512)|{ip:("192.0." + ((.+2)/256|floor|tostring) + "." + ((.%256)|tostring)),family:"ipv4",cfstRank:(.+1),sourceReliability:0.5}]' >"$tmp/large.json"
large_orders="$(cfip_adaptive_orders_json "$tmp/large.json")"
test "$(jq 'length' <<<"$(jq -c '.adaptiveOrder' <<<"$large_orders")")" = 512
test "$(jq 'length' <<<"$large_orders")" -lt 1000000

jq -n '[{ip:"1.1.1.1",family:"ipv4",eligible:true,lossRate:0,probeSummary:{totalMs:10,ttfbMs:5}},{ip:"2606:4700::1",family:"ipv6",eligible:true,lossRate:0,probeSummary:{totalMs:20,ttfbMs:5}},{ip:"2.2.2.2",family:"ipv4",eligible:true,lossRate:0,probeSummary:{totalMs:30,ttfbMs:5}},{ip:"2606:4700::2",family:"ipv6",eligible:false,lossRate:1,probeSummary:{totalMs:0,ttfbMs:0}}]' >"$tmp/full.json"
cfip_adaptive_make_audit_record "$tmp/guarded-plan.json" "$tmp/full.json" "$tmp/full.json" "$tmp/audit.json"
test "$(jq -r '.fullAudit' "$tmp/audit.json")" = true
test "$(jq -r '.fullNativeWinner' "$tmp/audit.json")" = 1.1.1.1
test "$(jq -r '.K25.selectedK' "$tmp/audit.json")" = 1
test "$(jq -r '.K40.selectedK' "$tmp/audit.json")" = 2
test "$(jq -r '.K60.selectedK' "$tmp/audit.json")" = 3
test "$(jq -r '.appliedCandidateRecall' "$tmp/audit.json")" = 1

for i in 1 2 3; do
    jq -n --argjson at "$((1000+i))" '{fullAudit:true,auditComplete:true,auditCensored:false,at:$at,contextFingerprint:"ctx",schedulerVersion:1,featureContractVersion:1,winnerRecall:1,topNRecall:1,severeMiss:0,eligibleInsufficiencyRate:0,probeSavings:0.3}' >"$tmp/audit.json"
    cfip_adaptive_record_audit "$tmp/audit.json"
done
test "$(jq -r '.qualificationState' "$CFIP_ADAPTIVE_STATE_FILE")" = qualified
test "$(cfip_adaptive_effective_mode)" = guarded
test "$(jq 'length' "$CFIP_ADAPTIVE_EVIDENCE_FILE")" = 3

CFIP_ADAPTIVE_NOW=1201
test "$(cfip_adaptive_qualification_is_usable; echo $?)" != 0
test "$(cfip_adaptive_effective_mode)" = shadow
test "$(jq -r '.qualificationState' "$CFIP_ADAPTIVE_STATE_FILE")" = stale

jq -n '{fullAudit:true,auditComplete:true,auditCensored:false,at:1201,contextFingerprint:"ctx",schedulerVersion:1,featureContractVersion:1,winnerRecall:0.5,topNRecall:0.5,severeMiss:0.2,eligibleInsufficiencyRate:0.1,probeSavings:0.3}' >"$tmp/negative.json"
cfip_adaptive_record_audit "$tmp/negative.json"
test "$(jq -r '.qualificationState' "$CFIP_ADAPTIVE_STATE_FILE")" = insufficient

printf '%s\n' "Adaptive pre-probe, shadow boundary, anchors, family coverage, evidence qualification, negative and stale gates passed"
