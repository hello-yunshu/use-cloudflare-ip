#!/usr/bin/env bash
# Deterministic long-running operational guardrails.  This module may lower
# effective modes, shorten reuse, or force audits; it never grants a mode that
# its qualification gate did not already authorize.

CFIP_OPERATIONAL_STATE_FILE="${CFIP_OPERATIONAL_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/operational-health.json}"
CFIP_OPERATIONAL_GUARDRAIL_APPLIED=false

cfip_operational_default_json() {
    jq -cn '{schemaVersion:1,state:"healthy",reasonCodes:[],adaptiveState:"unknown",candidateState:"unknown",reuseState:"unknown",lastFullOptimizeAt:null,lastAuditAt:null,lastFallbackAt:null,recommendedAction:"continue_current_policy",updatedAt:(now|floor),lastEvent:null}'
}

cfip_operational_state_json() {
    if [[ -s "$CFIP_OPERATIONAL_STATE_FILE" ]] && jq -e 'type=="object" and .schemaVersion==1 and (.state|IN("healthy","warning","degraded"))' "$CFIP_OPERATIONAL_STATE_FILE" >/dev/null 2>&1; then
        cat "$CFIP_OPERATIONAL_STATE_FILE"
    else
        cfip_operational_default_json
    fi
}

cfip_operational_reason_codes() {
    local event="${1:-}" adaptive='{}' qualification='{}' meta='{}' metrics='{}' reasons='[]'
    declare -F cfip_adaptive_state_json >/dev/null 2>&1 && adaptive="$(cfip_adaptive_state_json 2>/dev/null || printf '{}')"
    declare -F cfip_rill_qualification_json >/dev/null 2>&1 && qualification="$(cfip_rill_qualification_json 2>/dev/null || printf '{}')"
    [[ -s "${CFIP_RILL_STATE_META_FILE:-}" ]] && meta="$(jq -c . "$CFIP_RILL_STATE_META_FILE" 2>/dev/null || printf '{}')"
    [[ -s "${CFIP_PROBE_METRICS_FILE:-}" ]] && metrics="$(jq -c . "$CFIP_PROBE_METRICS_FILE" 2>/dev/null || printf '{}')"
    [[ "$(jq -r '.qualificationState // ""' <<<"$adaptive")" == stale ]] && reasons="$(jq -c '.+ ["adaptive_stale"]|unique' <<<"$reasons")"
    [[ "$(jq -r '.qualificationReason // ""' <<<"$adaptive")" == negative_evidence ]] && reasons="$(jq -c '.+ ["adaptive_regression"]|unique' <<<"$reasons")"
    [[ "$(jq -r '.adaptiveFallback // false' <<<"$metrics")" == true || "$event" == *fallback* || "$event" == *failed* ]] && reasons="$(jq -c '.+ ["measurement_budget_pressure"]|unique' <<<"$reasons")"
    if jq -e '((.state // .qualificationState // "")|tostring|test("regress|degrad|negative";"i"))' <<<"$qualification" >/dev/null 2>&1; then
        reasons="$(jq -c '.+ ["candidate_regression"]|unique' <<<"$reasons")"
    fi
    [[ "$(jq -r '.contextChanged // false' <<<"$meta")" == true ]] && reasons="$(jq -c '.+ ["context_changed"]|unique' <<<"$reasons")"
    [[ "$event" == reuse-failure* ]] && reasons="$(jq -c '.+ ["reuse_validation_failures"]|unique' <<<"$reasons")"
    printf '%s' "$reasons"
}

cfip_operational_apply_guardrails() {
    local state
    state="$(cfip_operational_state_json | jq -r '.state // "healthy"')"
    CFIP_OPERATIONAL_GUARDRAIL_APPLIED=false
    case "$state" in
        warning)
            CFIP_ADAPTIVE_AUDIT_INTERVAL=10
            CFIP_REUSE_MAX_FULL_OPTIMIZE_INTERVAL=3600
            CFIP_OPERATIONAL_GUARDRAIL_APPLIED=true
            ;;
        degraded)
            CFIP_ADAPTIVE_MEASUREMENT_MODE=shadow
            CFIP_ADAPTIVE_AUDIT_INTERVAL=1
            CFIP_RILL_MODE=shadow
            CFIP_REUSE_ENABLED=false
            CFIP_REUSE_MAX_FULL_OPTIMIZE_INTERVAL=300
            CFIP_OPERATIONAL_GUARDRAIL_APPLIED=true
            ;;
    esac
}

cfip_operational_update() {
    local event="${1:-run}" reason="${2:-}" state reasons adaptive_state candidate_state reuse_state severity recommended now
    state="$(cfip_operational_state_json)"
    reasons="$(cfip_operational_reason_codes "$event")"
    adaptive_state="$(cfip_adaptive_state_json 2>/dev/null | jq -r '.qualificationState // .effectiveMode // "unknown"' 2>/dev/null || printf unknown)"
    candidate_state="$(jq -r '.effectiveMode // "native"' "${CFIP_DECISION_FILE:-/dev/null}" 2>/dev/null || printf native)"
    reuse_state="$(jq -r '.actualPolicy // "unknown"' "${CFIP_REUSE_DECISION_FILE:-/dev/null}" 2>/dev/null || printf unknown)"
    if jq -e 'index("adaptive_regression") != null or index("candidate_regression") != null' <<<"$reasons" >/dev/null 2>&1; then
        severity=degraded; recommended=force_full_optimize_and_shadow
    elif [[ "$(jq 'length' <<<"$reasons")" -gt 0 ]]; then
        severity=warning; recommended=increase_audit_frequency_and_validate_reuse
    else
        severity=healthy; recommended=continue_current_policy
    fi
    now="$(date +%s)"
    jq -cn --argjson old "$state" --argjson reasons "$reasons" --arg state "$severity" --arg adaptive "$adaptive_state" --arg candidate "$candidate_state" --arg reuse "$reuse_state" --arg recommended "$recommended" --arg event "$event" --arg reason "$reason" --argjson now "$now" \
      '$old + {schemaVersion:1,state:$state,reasonCodes:$reasons,adaptiveState:$adaptive,candidateState:$candidate,reuseState:$reuse,recommendedAction:$recommended,updatedAt:$now,lastEvent:{name:$event,reason:(if $reason=="" then null else $reason end),at:$now}} | if $event=="full-optimize-success" then .lastFullOptimizeAt=$now elif $event=="adaptive-audit" then .lastAuditAt=$now elif ($event|test("fallback|failed")) then .lastFallbackAt=$now else . end' | cfip_atomic_write "$CFIP_OPERATIONAL_STATE_FILE"
}

cfip_operational_why_run() {
    if [[ "${CFIP_ADAPTIVE_AUDIT_DUE:-false}" == true ]]; then
        printf 'Periodic audit due'
    elif [[ "${CFIP_REUSE_ATTEMPTED:-false}" == true && -n "${CFIP_REUSE_FALLBACK_REASON:-}" ]]; then
        printf 'Full measurement: %s' "$CFIP_REUSE_FALLBACK_REASON"
    elif [[ "${CFIP_ADAPTIVE_EFFECTIVE_MODE:-off}" == guarded ]]; then
        printf 'Guarded K=%s: Context policy %s' "$(jq -r '.selectedK // 0' "${CFIP_ADAPTIVE_PLAN_FILE:-/dev/null}" 2>/dev/null || printf 0)" "$(cfip_context_policy_id 2>/dev/null || printf conservative-default)"
    elif [[ "${CFIP_ADAPTIVE_EFFECTIVE_MODE:-off}" == shadow ]]; then
        printf 'Adaptive Shadow: Insufficient fresh evidence'
    elif [[ "${CFIP_RILL_MODE:-off}" == assisted ]]; then
        printf 'Candidate Assisted: qualification-gated Native Safe Top-K'
    else
        printf 'Native measurement: Rill Shadow or disabled'
    fi
}
