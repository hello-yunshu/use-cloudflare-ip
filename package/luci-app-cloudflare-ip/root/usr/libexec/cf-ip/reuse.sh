#!/usr/bin/env bash
# Deterministic current-IP reuse policy. Native hard gates are the only
# authority; this path never invokes the Rill Runtime.

CFIP_REUSE_STATE_FILE="${CFIP_REUSE_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/reuse-policy.json}"
CFIP_REUSE_ATTEMPTED=false
CFIP_REUSE_FALLBACK_REASON=""

cfip_reuse_state_json() {
    if [[ -s "$CFIP_REUSE_STATE_FILE" ]] && jq -e 'type=="object" and .schemaVersion==1' "$CFIP_REUSE_STATE_FILE" >/dev/null 2>&1; then
        cat "$CFIP_REUSE_STATE_FILE"
        return 0
    fi
    if [[ -s "$CFIP_REUSE_STATE_FILE" ]]; then
        local stamp="$(date +%Y%m%d%H%M%S)" quarantine="${CFIP_REUSE_STATE_FILE}.quarantine.${stamp}"
        [[ -e "$quarantine" ]] && quarantine="$quarantine.$$"
        mv "$CFIP_REUSE_STATE_FILE" "$quarantine" 2>/dev/null || true
        cfip_log "reuse state quarantined: $quarantine"
    fi
    printf '%s\n' '{"schemaVersion":1,"lastFullOptimizeAt":0,"lastValidationAt":0,"validationSuccess":false,"configFingerprint":null,"reuseCount":0,"fullOptimizeCount":0,"savedProbes":0,"savedRuntimeSeconds":0,"recent":[]}'
}

cfip_reuse_config_fingerprint() {
    jq -cn --arg mode "$CFIP_MODE" --arg domains "${CFIP_TARGET_DOMAINS:-}" --arg ipType "$CFIP_IP_TYPE" \
      --arg protocol "$CFIP_SPEEDTEST_PROTOCOL" --arg pw "${CFIP_PASSWALL_TARGET_DOMAIN:-}" \
      --arg oc "${CFIP_OPENCLASH_CONFIG:-}:${CFIP_OPENCLASH_TARGET_DOMAIN:-}:${CFIP_OPENCLASH_TRANSPORT_FILTER:-}" \
      --arg policy "${CFIP_SOURCE_POLICY:-balanced}" '{mode:$mode,domains:$domains,ipType:$ipType,protocol:$protocol,passwall:$pw,openclash:$oc,sourcePolicy:$policy}' \
      | sha256sum | awk '{print $1}'
}

cfip_reuse_write_event() {
    local event="$1" reason="${2:-}" saved_probes="${3:-0}" saved_runtime="${4:-0}" state fp now
    state="$(cfip_reuse_state_json)"; fp="$(cfip_reuse_config_fingerprint)"; now="$(date +%s)"
    jq --arg event "$event" --arg reason "$reason" --arg fp "$fp" --argjson savedProbes "$saved_probes" --argjson savedRuntime "$saved_runtime" --argjson now "$now" \
      '. as $state | (($state.recent // []) + [{event:$event,reason:(if $reason=="" then null else $reason end),at:$now}])[-32:] as $recent |
       $state + {schemaVersion:1,configFingerprint:$fp,recent:$recent} |
       if $event=="full-optimize-success" then .lastFullOptimizeAt=$now | .lastValidationAt=$now | .validationSuccess=true | .fullOptimizeCount=((.fullOptimizeCount//0)+1)
       elif $event=="reuse-success" then .lastValidationAt=$now | .validationSuccess=true | .reuseCount=((.reuseCount//0)+1) | .savedProbes=((.savedProbes//0)+$savedProbes) | .savedRuntimeSeconds=((.savedRuntimeSeconds//0)+$savedRuntime)
       elif $event=="reuse-failure" then .lastValidationAt=$now | .validationSuccess=false
       else . end' <<<"$state" | cfip_atomic_write "$CFIP_REUSE_STATE_FILE"
}

cfip_reuse_hard_gate_reason() {
    local state fp now last_full last_validation
    [[ "${CFIP_REUSE_ENABLED:-true}" == true ]] || { printf 'reuse_disabled'; return 0; }
    [[ -s "${CFIP_STATUS_FILE:-}" ]] || { printf 'current_ip_missing'; return 0; }
    [[ "$(jq -r '(.best_ips|type=="array") and (.best_ips|length)>0' "$CFIP_STATUS_FILE" 2>/dev/null || printf false)" == true ]] || { printf 'current_ip_missing'; return 0; }
    state="$(cfip_reuse_state_json)"; fp="$(cfip_reuse_config_fingerprint)"; now="$(date +%s)"
    [[ "$(jq -r '.configFingerprint // empty' <<<"$state")" == "$fp" ]] || { printf 'configuration_changed'; return 0; }
    last_full="$(jq -r '.lastFullOptimizeAt // 0' <<<"$state")"; last_validation="$(jq -r '.lastValidationAt // 0' <<<"$state")"
    [[ "$last_full" =~ ^[0-9]+$ && $last_full -gt 0 ]] || { printf 'no_completed_full_optimize'; return 0; }
    ((now-last_full <= CFIP_REUSE_MAX_FULL_OPTIMIZE_INTERVAL)) || { printf 'full_optimize_interval_expired'; return 0; }
    [[ "$last_validation" =~ ^[0-9]+$ && $last_validation -gt 0 && "$(jq -r '.validationSuccess // false' <<<"$state")" == true ]] || { printf 'previous_validation_failed'; return 0; }
    [[ "$(jq -r '.last_result // "unknown"' "$CFIP_STATUS_FILE")" == success ]] || { printf 'recent_run_failed'; return 0; }
    return 1
}

cfip_reuse_record_decision() {
    local actual="$1" forced="${2:-false}" reason="${3:-}" output="${CFIP_REUSE_DECISION_FILE:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/reuse-decision.json}"
    jq -cn --arg actual "$actual" --argjson forced "$forced" --arg reason "$reason" \
      '{schemaVersion:1,decisionKind:"native-reuse",actualPolicy:$actual,forced:$forced,reason:(if $reason=="" then null else $reason end),authority:"native-hard-gate",at:(now|floor)}' | cfip_atomic_write "$output"
}

cfip_reuse_try_current() {
    local reason current probe_output saved_probes saved_runtime="0" start
    CFIP_REUSE_ATTEMPTED=false
    reason="$(cfip_reuse_hard_gate_reason)" || reason=""
    if [[ -n "$reason" ]]; then
        CFIP_REUSE_FALLBACK_REASON="$reason"
        cfip_reuse_record_decision FULL_OPTIMIZE true "$reason"
        return 1
    fi
    current="$(mktemp "${TMPDIR:-/tmp}/cfip-reuse-current.XXXXXX")" || return 1
    jq '[.best_ips[]? as $ip | {ip:$ip,family:(if ($ip|contains(":")) then "ipv6" else "ipv4" end),origin:"reuse-current",sources:["current"],sourceClass:"current",sourceCount:0,stale:false}]' "$CFIP_STATUS_FILE" | jq --argjson n "$CFIP_IP_COUNT" '.[0:$n]' >"$current"
    [[ "$(jq 'length' "$current")" == "$CFIP_IP_COUNT" ]] || { rm -f "$current"; CFIP_REUSE_FALLBACK_REASON=current_ip_count_insufficient; cfip_reuse_record_decision FULL_OPTIMIZE true "$CFIP_REUSE_FALLBACK_REASON"; return 1; }
    start="$(date +%s)"; CFIP_PHASE=reuse_validation; CFIP_MEASUREMENT_STARTED_AT="$(cfip_monotonic_seconds)"; CFIP_MEASUREMENT_DEADLINE=$((CFIP_MEASUREMENT_STARTED_AT+CFIP_REUSE_VALIDATION_TIMEOUT))
    CFIP_REUSE_ATTEMPTED=true
    cp "$current" "$CFIP_SELECTED_FILE"
    probe_output="$(mktemp "${TMPDIR:-/tmp}/cfip-reuse-outcome.XXXXXX")" || { rm -f "$current"; return 1; }
    if ! cfip_post_apply_probe "$current" "$CFIP_TARGET_DOMAINS" "$CFIP_REUSE_VALIDATION_TIMEOUT" "$probe_output"; then
        CFIP_REUSE_FALLBACK_REASON=current_validation_failed
        cfip_reuse_record_decision FULL_OPTIMIZE false "$CFIP_REUSE_FALLBACK_REASON"
        cfip_reuse_write_event reuse-failure "$CFIP_REUSE_FALLBACK_REASON"
        declare -F cfip_operational_record_event >/dev/null 2>&1 && cfip_operational_record_event reuse-failure "$CFIP_REUSE_FALLBACK_REASON" validation_failure
        rm -f "$current" "$probe_output"; return 1
    fi
    if ! jq -e --argjson loss "$CFIP_REUSE_LOSS_LIMIT" --argjson ttfb "$CFIP_REUSE_TTFB_LIMIT" --argjson total "$CFIP_REUSE_TOTAL_LIMIT" \
      'all(.probes[]; .success==true and (.lossRate//0)<=$loss and (.ttfbMs//999999)<=$ttfb and (.totalMs//999999)<=$total)' "$probe_output" >/dev/null 2>&1; then
        CFIP_REUSE_FALLBACK_REASON=current_quality_regression
        cfip_reuse_record_decision FULL_OPTIMIZE false "$CFIP_REUSE_FALLBACK_REASON"
        cfip_reuse_write_event reuse-failure "$CFIP_REUSE_FALLBACK_REASON"
        declare -F cfip_operational_record_event >/dev/null 2>&1 && cfip_operational_record_event reuse-failure "$CFIP_REUSE_FALLBACK_REASON" validation_failure
        rm -f "$current" "$probe_output"; return 1
    fi
    saved_probes="$(jq '.probes // [] | length' "$probe_output" 2>/dev/null || printf 0)"; saved_runtime="$(( $(date +%s)-start ))"
    cfip_reuse_record_decision REUSE_CURRENT false "validated_current_ip"
    cp "$probe_output" "$CFIP_OUTCOME_FILE"
    cfip_reuse_write_event reuse-success validated_current_ip "$saved_probes" "$saved_runtime"
    rm -f "$current" "$probe_output"
    CFIP_MEASUREMENT_DEADLINE=0
    return 0
}
