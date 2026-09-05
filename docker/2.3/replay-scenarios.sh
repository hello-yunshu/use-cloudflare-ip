#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES="${1:-$ROOT/docker/2.3/fixtures/scenarios.json}"
OUTPUT="${2:-$ROOT/docker/2.3/results/replay-evidence.json}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUTPUT")" "$TMP/status"

export CFIP_STATUS_DIR="$TMP/status" CFIP_IP_COUNT=1 CFIP_IP_TYPE=ipv4
export CFIP_ADAPTIVE_MEASUREMENT_ENABLED=true CFIP_ADAPTIVE_MEASUREMENT_MODE=shadow
export CFIP_ADAPTIVE_TARGET_RATIO_PERCENT=40 CFIP_ADAPTIVE_MIN_PROBE_COUNT=8
export CFIP_ADAPTIVE_MAX_PROBE_COUNT=60 CFIP_ADAPTIVE_EXPANSION_BATCH_SIZE=8
export CFIP_ADAPTIVE_CONTEXT_FINGERPRINT=replay CFIP_RUN_ID=replay
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"

scenario_count="$(jq 'length' "$FIXTURES")"
results='[]'
for index in $(seq 0 $((scenario_count - 1))); do
    scenario="$(jq -c ".[$index]" "$FIXTURES")"
    name="$(jq -r '.name' <<<"$scenario")"
    family="$(jq -r '.family' <<<"$scenario")"
    pool="$(jq -r '.poolSize' <<<"$scenario")"
    ip_count="$(jq -r '.ipCount' <<<"$scenario")"
    mode="$(jq -r '.mode' <<<"$scenario")"
    history="$(jq -r '.history' <<<"$scenario")"
    fallback="$(jq -r '.fallback // false' <<<"$scenario")"
    expansion="$(jq -r '.expansionCount // 0' <<<"$scenario")"
    input="$TMP/$index-input.json"
    plan="$TMP/$index-plan.json"
    native="$TMP/$index-native.json"
    full="$TMP/$index-full.json"
    metrics="$TMP/$index-metrics.json"
    audit="$TMP/$index-audit.json"
    jq -n --arg family "$family" --arg history "$history" --argjson n "$pool" '[range(0;$n) | {ip:(if $family=="ipv6" then ("2001:db8:" + ((.+1)|tostring) + "::1") elif $family=="both" and (. % 2)==1 then ("2001:db8:" + ((.+1)|tostring) + "::1") else ("198.51.100." + (((.%250)+1)|tostring)) end),family:(if $family=="both" then (if (. % 2)==1 then "ipv6" else "ipv4" end) else $family end),cfstRank:(.+1),sourceCount:(if $history=="cold" then 1 else 2 end),sourceReliability:(if $history=="degraded" then 0.3 else 0.8 end),sourceStale:($history=="stale"),previousWinner:($history=="stable" and .==0)}]' >"$input"
    export CFIP_IP_COUNT="$ip_count" CFIP_IP_TYPE="$family" CFIP_ADAPTIVE_MEASUREMENT_MODE="$mode" CFIP_ADAPTIVE_RUN_SEQUENCE="$index" CFIP_ADAPTIVE_CONTEXT_FINGERPRINT="$name" CFIP_PROBE_METRICS_FILE="$metrics"
    cfip_adaptive_write_plan "$input" "$plan"
    jq '[.[] | . + {eligible:true,lossRate:0.02,downloadMBps:100,probes:[{errorClass:"none"}],probeSummary:{probeCount:1,successCount:1,totalMs:40,ttfbMs:20}}]' "$input" >"$full"
    jq '[.[] | . + {eligible:true,lossRate:0.02,downloadMBps:100,probeSummary:{probeCount:1,successCount:1,totalMs:40,ttfbMs:20}}] | sort_by(.probeSummary.totalMs,.cfstRank,.ip) | to_entries | map(.value + {nativeRank:(.key+1)})' "$input" >"$native"
    jq -n --argjson expansion "$expansion" --argjson fallback "$fallback" --argjson planned "$(jq '.selectedK' "$plan")" --argjson actual "$(jq '.selectedK' "$plan")" --argjson full "$pool" --arg mode "$mode" --argjson audit "$(jq -r '.fallback // false' <<<"$scenario")" --argjson measurement "$((pool + 10))" --argjson scheduler 1 --argjson probe "$((pool * 2))" '{schemaVersion:1,measurementDurationMs:$measurement,schedulerDurationMs:$scheduler,probeDurationMs:$probe,fullCandidateCount:$full,plannedK:$planned,actualUniqueProbeCount:$actual,expansionCount:$expansion,fallbackUsed:$fallback,auditRun:$audit,effectiveAdaptiveMode:$mode,effectiveCandidateMode:"off",timingMode:"replayed"}' >"$metrics"
    cfip_adaptive_make_audit_record "$plan" "$native" "$full" "$audit" 0
    result="$(jq -cn --arg name "$name" --arg family "$family" --arg history "$history" --arg mode "$mode" --argjson ipCount "$ip_count" --argjson pool "$pool" --argjson planned "$(jq '.selectedK' "$plan")" --argjson actual "$(jq '.selectedK' "$plan")" --argjson audit "$(cat "$audit")" --argjson metrics "$(cat "$metrics")" --argjson fallback "$fallback" --argjson expansion "$expansion" '{scenario:$name,context:{family:$family,history:$history,poolSize:$pool,ipCount:$ipCount},mode:$mode,timingMode:"replayed",environment:"macbook-docker-replay",candidateCount:$pool,fullCandidateCount:$pool,plannedK:$planned,actualUniqueProbeCount:$actual,probeReductionRatio:(1-($actual/$pool)),measurementDurationMs:$metrics.measurementDurationMs,schedulerDurationMs:$metrics.schedulerDurationMs,probeDurationMs:$metrics.probeDurationMs,auditRun:$metrics.auditRun,effectiveAdaptiveMode:$metrics.effectiveAdaptiveMode,effectiveCandidateMode:$metrics.effectiveCandidateMode,winnerRecall:($audit.winnerRecall//1),topNRecall:($audit.topNRecall//1),eligibleInsufficiencyRate:($audit.eligibleInsufficiencyRate//0),severeMissRate:($audit.severeMiss//0),expansionRate:(if $pool>0 then $expansion/$pool else 0 end),fallbackRate:(if $fallback then 1 else 0 end),auditCostRatio:1,fallbackUsed:$fallback,expansionCount:$expansion}')"
    results="$(jq --argjson item "$result" '. + [$item]' <<<"$results")"
done

jq -n --argjson scenarios "$results" --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{schemaVersion:1,kind:"cloudflare-ip-adaptive-evidence",generatedAt:$generatedAt,environment:"macbook-docker-replay",timingMode:"replayed",physicalOpenwrt:"SKIPPED (user-approved)",soak:"SKIPPED (user-approved)",scenarios:$scenarios}' >"$OUTPUT"
printf '%s\n' "$OUTPUT"
