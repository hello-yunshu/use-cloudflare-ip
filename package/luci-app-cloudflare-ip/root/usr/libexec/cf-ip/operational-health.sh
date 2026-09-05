#!/usr/bin/env bash
# Deterministic long-running operational guardrails.  This module may lower
# effective modes, shorten reuse, or force audits; it never grants a mode that
# its qualification gate did not already authorize.

CFIP_OPERATIONAL_STATE_FILE="${CFIP_OPERATIONAL_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/operational-health.json}"
CFIP_OPERATIONAL_HISTORY_FILE="${CFIP_OPERATIONAL_HISTORY_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/operational-history.json}"
CFIP_OPERATIONAL_HISTORY_LIMIT=100
CFIP_OPERATIONAL_ROLLING_WINDOW=20
CFIP_OPERATIONAL_MIN_SAMPLES=5
CFIP_OPERATIONAL_GUARDRAIL_APPLIED=false

cfip_operational_history_json() {
    local stamp quarantine history_file="${CFIP_OPERATIONAL_HISTORY_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/operational-history.json}"
    if [[ -s "$history_file" ]] && jq -e 'type=="object" and .schemaVersion==1 and (.records|type)=="array"' "$history_file" >/dev/null 2>&1; then
        cat "$history_file"
        return 0
    fi
    if [[ -s "$history_file" ]]; then
        stamp="$(date +%Y%m%d%H%M%S)"; quarantine="${history_file}.quarantine.${stamp}"
        [[ -e "$quarantine" ]] && quarantine="$quarantine.$$"
        mv "$history_file" "$quarantine" 2>/dev/null || true
        cfip_log "operational history quarantined: $quarantine" 2>/dev/null || true
    fi
    printf '%s\n' '{"schemaVersion":1,"records":[]}'
}

cfip_operational_upsert_record() {
    local item="$1" history next limit="${CFIP_OPERATIONAL_HISTORY_LIMIT:-100}" history_file="${CFIP_OPERATIONAL_HISTORY_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/operational-history.json}"
    history="$(cfip_operational_history_json)"
    next="$(jq --argjson item "$item" --argjson limit "$limit" '
      .records as $records |
      (if any($records[]?; .runId == $item.runId) then
        $records | map(if .runId == $item.runId then
          . * $item |
          .reuseResult=(if $item.reuseResult == "validation_failure" then "validation_failure" else (.reuseResult // $item.reuseResult // null) end) |
          .completed=(if $item.completed == true then true else (.completed // false) end)
        else . end)
       else ($records + [$item]) end) | .[-$limit:] as $bounded |
      {schemaVersion:1,records:$bounded}' <<<"$history")" || return 1
    printf '%s\n' "$next" | cfip_atomic_write "$history_file"
}

cfip_operational_rollup_json() {
    local history="${1:-$(cfip_operational_history_json)}" window="${CFIP_OPERATIONAL_ROLLING_WINDOW:-20}" minimum="${CFIP_OPERATIONAL_MIN_SAMPLES:-5}"
    jq --argjson window "$window" --argjson minimum "$minimum" '
      def completed: [.records[] | select(.completed == true)][-$window:];
      def rate($values): if ($values|length)==0 then null else (($values|map(select(. != null and . == true))|length) / ($values|length)) end;
      def numeric_mean($values): (($values|map(select(type=="number"))) as $v | if ($v|length)==0 then null else ($v|add/length) end);
      (completed) as $runs |
      ([ $runs[] | select(.auditRun == true and (.winnerRecall|type)=="number" and (.topNRecall|type)=="number" and (.severeMiss|type)=="number") ]) as $audits |
      ([ $runs[] | select(.reuseAttempted == true) ]) as $reuse |
      {
        windowSize:($runs|length),
        minimumMeaningfulSamples:$minimum,
        meaningful: (($runs|length) >= $minimum),
        runFailureRate: rate([$runs[] | if (.result == "success") then false elif .result == null then null else true end]),
        fallbackRate: rate([$runs[].fallbackUsed]),
        expansionRunRate: rate([$runs[] | if (.expansionCount|type)=="number" then (.expansionCount > 0) else null end]),
        reuseValidationFailureRate: rate([$reuse[] | if .reuseResult == "validation_failure" then true elif .reuseResult == "success" then false else null end]),
        comparableAuditCount:($audits|length),
        winnerRecallMean:numeric_mean([$audits[].winnerRecall]),
        topNRecallMean:numeric_mean([$audits[].topNRecall]),
        severeMissRate:numeric_mean([$audits[].severeMiss]),
        adaptiveRegression: any($runs[]?; ((.adaptiveQualificationState // "")|tostring|test("negative|regress|degrad";"i"))),
        candidateRegression: any($runs[]?; ((.candidateQualificationState // "")|tostring|test("negative|regress|degrad";"i")))
      }' <<<"$history"
}

cfip_operational_record_item() {
    local completed="${1:-true}" result="${2:-}" reuse_result="${3:-}" now metrics='{}' adaptive='{}' qualification='{}' decision='{}' transaction='{}' audit='{}' context=''
    [[ -s "${CFIP_PROBE_METRICS_FILE:-}" ]] && metrics="$(jq -c . "$CFIP_PROBE_METRICS_FILE" 2>/dev/null || printf '{}')"
    [[ -s "${CFIP_ADAPTIVE_STATE_FILE:-}" ]] && adaptive="$(jq -c . "$CFIP_ADAPTIVE_STATE_FILE" 2>/dev/null || printf '{}')"
    declare -F cfip_rill_qualification_json >/dev/null 2>&1 && qualification="$(cfip_rill_qualification_json 2>/dev/null || printf '{}')"
    [[ -s "${CFIP_DECISION_FILE:-}" ]] && decision="$(jq -c . "$CFIP_DECISION_FILE" 2>/dev/null || printf '{}')"
    [[ -s "${CFIP_TXN_RESULT_FILE:-}" ]] && transaction="$(jq -c . "$CFIP_TXN_RESULT_FILE" 2>/dev/null || printf '{}')"
    [[ -s "${CFIP_ADAPTIVE_AUDIT_FILE:-}" ]] && audit="$(jq -c . "$CFIP_ADAPTIVE_AUDIT_FILE" 2>/dev/null || printf '{}')"
    context="${CFIP_ADAPTIVE_CONTEXT_FINGERPRINT:-}"
    [[ -n "$context" ]] || context="$(jq -r '.contextFingerprint // .lastContextFingerprint // empty' <<<"$adaptive" 2>/dev/null || true)"
    now="$(date +%s)"
    jq -cn --arg runId "${CFIP_RUN_ID:-}" --arg result "$result" --arg proxy "${CFIP_MODE:-}" \
      --arg adaptiveRequested "${CFIP_ADAPTIVE_MEASUREMENT_MODE:-}" --arg adaptiveEffective "$(jq -r '.effectiveAdaptiveMode // empty' <<<"$metrics")" \
      --arg adaptiveQualification "$(jq -r '.qualificationState // empty' <<<"$adaptive")" --arg candidateRequested "${CFIP_RILL_MODE:-}" \
      --arg candidateEffective "$(jq -r '.effectiveMode // empty' <<<"$decision")" --arg candidateQualification "$(jq -r '.state // .qualificationState // empty' <<<"$qualification")" \
      --arg context "$context" --arg reuseResult "$reuse_result" --argjson completed "$completed" --argjson at "$now" \
      --argjson metrics "$metrics" --argjson audit "$audit" --argjson transaction "$transaction" \
      '{schemaVersion:1,at:$at,runId:(if $runId=="" then null else $runId end),completed:$completed,result:(if $result=="" then null else $result end),proxyMode:(if $proxy=="" then null else $proxy end),adaptiveRequestedMode:(if $adaptiveRequested=="" then null else $adaptiveRequested end),adaptiveEffectiveMode:(if $adaptiveEffective=="" then null else $adaptiveEffective end),adaptiveQualificationState:(if $adaptiveQualification=="" then null else $adaptiveQualification end),candidateRequestedMode:(if $candidateRequested=="" then null else $candidateRequested end),candidateEffectiveMode:(if $candidateEffective=="" then null else $candidateEffective end),candidateQualificationState:(if $candidateQualification=="" then null else $candidateQualification end),fullCandidateCount:($metrics.fullCandidateCount // null),plannedK:($metrics.plannedK // null),actualUniqueProbeCount:($metrics.actualUniqueProbeCount // null),expansionCount:($metrics.expansionCount // null),fallbackUsed:($metrics.fallbackUsed // null),auditRun:($metrics.auditRun // ($audit.fullAudit // false)),winnerRecall:($audit.winnerRecall // null),topNRecall:($audit.topNRecall // null),severeMiss:($audit.severeMiss // null),reuseAttempted:(if $reuseResult=="" then false else true end),reuseResult:(if $reuseResult=="" then null else $reuseResult end),transactionApplied:($transaction.success // null),measurementDurationMs:($metrics.measurementDurationMs // null),probeDurationMs:($metrics.probeDurationMs // null),contextFingerprint:(if $context=="" then null else $context end)}'
}

cfip_operational_record_event() {
    local event="${1:-}" result="${2:-}" reuse_result="${3:-}"
    local item
    [[ -n "${CFIP_RUN_ID:-}" ]] || return 0
    item="$(cfip_operational_record_item false "$result" "$reuse_result")" || return 1
    cfip_operational_upsert_record "$item" || return 1
    [[ "$event" == reuse-failure* ]] && cfip_operational_update reuse-failure "$result" || true
}

cfip_operational_record_run() {
    local result="${CFIP_LAST_RESULT:-}" reuse_result=""
    if [[ "${CFIP_REUSE_ATTEMPTED:-false}" == true ]]; then
        if [[ "$(jq -r '.actualPolicy // empty' "${CFIP_REUSE_DECISION_FILE:-/dev/null}" 2>/dev/null || true)" == REUSE_CURRENT ]]; then
            reuse_result=success
        elif [[ "${CFIP_REUSE_FALLBACK_REASON:-}" == current_validation_failed || "${CFIP_REUSE_FALLBACK_REASON:-}" == current_quality_regression ]]; then
            reuse_result=validation_failure
        fi
    fi
    local item
    item="$(cfip_operational_record_item true "$result" "$reuse_result")" || return 1
    cfip_operational_upsert_record "$item"
}

cfip_operational_default_json() {
    jq -cn --argjson rolling "$(cfip_operational_rollup_json)" '{schemaVersion:1,state:"healthy",reasonCodes:[],adaptiveState:"unknown",candidateState:"unknown",reuseState:"unknown",rolling:$rolling,lastFullOptimizeAt:null,lastAuditAt:null,lastFallbackAt:null,recommendedAction:"continue_current_policy",updatedAt:(now|floor),lastEvent:null}'
}

cfip_operational_state_json() {
    local state_file="${CFIP_OPERATIONAL_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/operational-health.json}"
    if [[ -s "$state_file" ]] && jq -e 'type=="object" and .schemaVersion==1 and (.state|IN("healthy","warning","degraded"))' "$state_file" >/dev/null 2>&1; then
        cat "$state_file"
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
    local event="${1:-run}" reason="${2:-}" state reasons adaptive_state candidate_state reuse_state severity recommended now rolling
    state="$(cfip_operational_state_json)"
    reasons="$(cfip_operational_reason_codes "$event")"
    rolling="$(cfip_operational_rollup_json)"
    adaptive_state="$(cfip_adaptive_state_json 2>/dev/null | jq -r '.qualificationState // .effectiveMode // "unknown"' 2>/dev/null || printf unknown)"
    candidate_state="$(jq -r '.effectiveMode // "native"' "${CFIP_DECISION_FILE:-/dev/null}" 2>/dev/null || printf native)"
    reuse_state="$(jq -r '.actualPolicy // "unknown"' "${CFIP_REUSE_DECISION_FILE:-/dev/null}" 2>/dev/null || printf unknown)"
    if jq -e --argjson rolling "$rolling" --argjson reasons "$reasons" '($reasons|index("adaptive_regression")) != null or ($reasons|index("candidate_regression")) != null or $rolling.adaptiveRegression == true or $rolling.candidateRegression == true or ($rolling.meaningful == true and (($rolling.runFailureRate // 0) >= 0.40 or ($rolling.reuseValidationFailureRate // 0) >= 0.50 or ($rolling.severeMissRate // 0) >= 0.20))' <<<"{}" >/dev/null 2>&1; then
        severity=degraded; recommended=force_full_optimize_and_shadow
    elif jq -e --argjson rolling "$rolling" --argjson reasons "$reasons" '($rolling.meaningful == true and (($rolling.runFailureRate // 0) >= 0.20 or ($rolling.fallbackRate // 0) >= 0.30 or ($rolling.expansionRunRate // 0) >= 0.50 or ($rolling.reuseValidationFailureRate // 0) >= 0.25)) or ($rolling.meaningful == false and ($rolling.windowSize // 0) > 0) or (($reasons|length) > 0)' <<<"{}" >/dev/null 2>&1; then
        severity=warning; recommended=increase_audit_frequency_and_validate_reuse
    else
        severity=healthy; recommended=continue_current_policy
    fi
    now="$(date +%s)"
    jq -cn --argjson old "$state" --argjson rolling "$rolling" --argjson reasons "$reasons" --arg state "$severity" --arg adaptive "$adaptive_state" --arg candidate "$candidate_state" --arg reuse "$reuse_state" --arg recommended "$recommended" --arg event "$event" --arg reason "$reason" --argjson now "$now" \
      '$old + {schemaVersion:1,state:$state,reasonCodes:$reasons,adaptiveState:$adaptive,candidateState:$candidate,reuseState:$reuse,rolling:$rolling,recommendedAction:$recommended,updatedAt:$now,lastEvent:{name:$event,reason:(if $reason=="" then null else $reason end),at:$now}} | if $event=="full-optimize-success" then .lastFullOptimizeAt=$now elif $event=="adaptive-audit" then .lastAuditAt=$now elif ($event|test("fallback|failed")) then .lastFallbackAt=$now else . end' | cfip_atomic_write "${CFIP_OPERATIONAL_STATE_FILE:-${CFIP_STATUS_DIR:-/etc/cf_ip}/operational-health.json}"
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
