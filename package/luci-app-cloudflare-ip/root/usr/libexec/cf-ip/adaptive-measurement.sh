#!/usr/bin/env bash
# Native adaptive measurement. It schedules probes only and never creates a
# Runtime/Rill learner or partition.
# shellcheck shell=bash

CFIP_ADAPTIVE_SCHEDULER_VERSION=1
CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION=1
CFIP_ADAPTIVE_STATE_FILE="$CFIP_STATUS_DIR/adaptive-measurement-state.json"
CFIP_ADAPTIVE_EVIDENCE_FILE="$CFIP_STATUS_DIR/adaptive-measurement-evidence.json"
CFIP_ADAPTIVE_EVIDENCE_LIMIT=100
CFIP_ADAPTIVE_EVIDENCE_MAX_BYTES=524288

cfip_adaptive_default_state_json() {
    jq -cn --argjson scheduler "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson contract "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" \
      '{schemaVersion:1,requestedMode:"shadow",effectiveMode:"shadow",qualificationState:"insufficient",qualificationReason:"no_eligible_audit_evidence",evidenceCount:0,freshAt:null,contextFingerprint:null,lastContextFingerprint:null,schedulerVersion:$scheduler,featureContractVersion:$contract,targetRatioPercent:25,minProbeCount:8,explorationRatioPercent:10,selectedK:0,lastRunId:null,runCount:0,auditSequence:0,lastAuditAt:null,lastFallbackReason:null,lastExpansionCount:0,updatedAt:(now|floor)}'
}

cfip_adaptive_state_json() {
    if [[ -s "$CFIP_ADAPTIVE_STATE_FILE" ]] && jq -e 'type=="object" and .schemaVersion==1' "$CFIP_ADAPTIVE_STATE_FILE" >/dev/null 2>&1; then
        cat "$CFIP_ADAPTIVE_STATE_FILE"
    else
        cfip_adaptive_default_state_json
    fi
}

cfip_adaptive_evidence_json() {
    local bytes
    bytes=0
    [[ -e "$CFIP_ADAPTIVE_EVIDENCE_FILE" ]] && bytes="$(wc -c <"$CFIP_ADAPTIVE_EVIDENCE_FILE" 2>/dev/null || printf 0)"
    if [[ -s "$CFIP_ADAPTIVE_EVIDENCE_FILE" ]] && ((bytes <= CFIP_ADAPTIVE_EVIDENCE_MAX_BYTES)) && \
       jq -e --argjson limit "$CFIP_ADAPTIVE_EVIDENCE_LIMIT" 'type=="array" and length<=$limit' "$CFIP_ADAPTIVE_EVIDENCE_FILE" >/dev/null 2>&1; then
        cat "$CFIP_ADAPTIVE_EVIDENCE_FILE"
    else
        [[ -s "$CFIP_ADAPTIVE_EVIDENCE_FILE" ]] && mv "$CFIP_ADAPTIVE_EVIDENCE_FILE" "$CFIP_ADAPTIVE_EVIDENCE_FILE.quarantine.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        printf '[]\n'
    fi
}

cfip_adaptive_contract_json() {
    jq -cn --argjson version "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" \
      '{version:$version,fields:["cfstRank","family","sourceCount","sources","origin","sourceStale","sourceReliability","historyMedianTotalMs","historyP95TotalMs","historyEWMA","historyConsecutiveFailures","historyLastSeen","prefixHistory","coloHistory","previousWinner","candidateId","ip"],forbiddenFields:["probes","probeSummary","eligible","lossRate","avgLatencyMs","downloadMBps","sent","received","targetProbe","currentRunMetrics"],rule:"Only pre-probe fields may reach the adaptive scheduler."}'
}

cfip_adaptive_orders_json() {
    local input="$1" candidates
    [[ -s "$input" ]] || return 1
    candidates="$(jq -c 'if type=="array" then . else [] end' "$input")" || return 1
    jq -cn --argjson candidates "$candidates" --argjson scheduler "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson contract "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" '
      ($candidates|map({candidateId:(.candidateId // ("cfst:" + (.ip|tostring))),ip:(.ip|tostring),family:(.family // "unknown"),cfstRank:(.cfstRank // 999999),sourceCount:(.sourceCount // 0),sources:(.sources // []),origin:(.origin // "unknown"),sourceStale:(.sourceStale // false),sourceReliability:(.sourceReliability // 0.5),historyMedianTotalMs:(.historyMedianTotalMs // null),historyP95TotalMs:(.historyP95TotalMs // null),historyEWMA:(.historyEWMA // null),historyConsecutiveFailures:(.historyConsecutiveFailures // 0),historyLastSeen:(.historyLastSeen // 0),prefixHistory:(.prefixHistory // null),coloHistory:(.coloHistory // null),previousWinner:(.previousWinner // false)})) as $c |
      ($c|sort_by(.cfstRank,.ip)) as $baseline |
      ($c|map(. + {adaptiveScore:((1000000/(1+(.cfstRank|tonumber))) + ((.sourceReliability|tonumber)*10000) + (if .sourceStale then 0 else 500 end) + (if .previousWinner then 20000 else 0 end) - ((.historyConsecutiveFailures|tonumber)*1000))})) as $scored |
      ($scored|sort_by(-.adaptiveScore,.cfstRank,.ip)) as $adaptive |
      {schemaVersion:1,schedulerVersion:$scheduler,featureContractVersion:$contract,candidateCount:($c|length),baselineOrder:($baseline|map(.ip)),cfstOrder:($baseline|map(.ip)),adaptiveOrder:($adaptive|map(.ip)),candidates:$c,scoredCandidates:$adaptive}'
}

cfip_adaptive_write_plan() {
    local input="$1" output="$2" orders candidates n ratio min max explore_count k selected remaining anchor previous family ip
    orders="$(cfip_adaptive_orders_json "$input")" || return 1
    candidates="$(jq -c '.candidates' <<<"$orders")"; n="$(jq 'length' <<<"$candidates")"
    ratio="$CFIP_ADAPTIVE_TARGET_RATIO_PERCENT"; min="$CFIP_ADAPTIVE_MIN_PROBE_COUNT"; max="$CFIP_ADAPTIVE_MAX_PROBE_COUNT"; explore_count="${CFIP_ADAPTIVE_EXPLORATION_RATIO_PERCENT:-10}"
    [[ "$ratio" =~ ^[0-9]+$ ]] || ratio=25; [[ "$min" =~ ^[1-9][0-9]*$ ]] || min=8; [[ "$max" =~ ^[1-9][0-9]*$ ]] || max=60; [[ "$explore_count" =~ ^[0-9]+$ ]] || explore_count=10
    k="$(jq -nr --argjson n "$n" --argjson ratio "$ratio" --argjson min "$min" --argjson max "$max" --argjson required "$CFIP_IP_COUNT" '([$required,(($n*$ratio+99)/100|floor),$min]|max) as $v|[$v,$n,$max]|min')"
    ((k < CFIP_IP_COUNT)) && k="$CFIP_IP_COUNT"; ((k > n)) && k="$n"
    selected='[]'; anchor="$(jq -r '.baselineOrder[0] // empty' <<<"$orders")"
    [[ -n "$anchor" ]] && selected="$(jq -cn --argjson a "$selected" --arg ip "$anchor" '$a+[$ip]|unique')"
    previous="$(jq -r '.scoredCandidates[]|select(.previousWinner==true)|.ip' <<<"$orders" | head -n1)"
    [[ -n "$previous" ]] && selected="$(jq -cn --argjson a "$selected" --arg ip "$previous" '$a+[$ip]|unique')"
    if [[ "$CFIP_IP_TYPE" == both ]]; then
        for family in ipv4 ipv6; do
            ip="$(jq -r --arg family "$family" '.scoredCandidates[]|select(.family==$family)|.ip' <<<"$orders" | head -n1)"
            [[ -n "$ip" ]] && selected="$(jq -cn --argjson a "$selected" --arg ip "$ip" '$a+[$ip]|unique')"
        done
    fi
    explore_count="$((k*explore_count/100))"
    selected="$(jq -cn --argjson a "$selected" --argjson ranked "$(jq -c '.adaptiveOrder' <<<"$orders")" --argjson tail "$(jq -c '.adaptiveOrder|reverse' <<<"$orders")" --argjson k "$k" --argjson e "$explore_count" '($a+[$tail[0:$e][]]+$ranked) as $all|reduce $all[] as $ip ([];if index($ip) then . else .+[$ip] end)|.[0:$k]')"
    remaining="$(jq -cn --argjson c "$candidates" --argjson selected "$selected" '$c|map(select((.ip as $ip|$selected|index($ip))==null))')"
    jq -cn --argjson orders "$orders" --argjson selected "$selected" --argjson remaining "$remaining" --argjson k "$k" --arg mode "$CFIP_ADAPTIVE_EFFECTIVE_MODE" --argjson ratio "$ratio" --argjson min "$min" --argjson max "$max" \
      '$orders+{selectedK:$k,selectedIps:$selected,remainingCandidates:$remaining,effectiveMode:$mode,targetRatioPercent:$ratio,minProbeCount:$min,maxProbeCount:$max,mandatoryAnchors:$selected}' | cfip_atomic_write "$output"
}

cfip_adaptive_qualification_is_usable() {
    local state fresh now max context
    state="$(cfip_adaptive_state_json)"
    [[ "$(jq -r '.qualificationState // "insufficient"' <<<"$state")" == qualified ]] || return 1
    fresh="$(jq -r '.freshAt // 0' <<<"$state")"; now="$CFIP_ADAPTIVE_NOW"; max="$CFIP_ADAPTIVE_EVALUATION_MAX_AGE_SECONDS"
    [[ "$fresh" =~ ^[0-9]+$ && "$max" =~ ^[1-9][0-9]*$ ]] || return 1; ((now-fresh <= max)) || return 1
    context="$CFIP_ADAPTIVE_CONTEXT_FINGERPRINT"
    [[ -z "$context" || "$context" == "$(jq -r '.contextFingerprint // ""' <<<"$state")" ]] || return 1
    [[ "$(jq -r '.schedulerVersion // 0' <<<"$state")" == "$CFIP_ADAPTIVE_SCHEDULER_VERSION" && "$(jq -r '.featureContractVersion // 0' <<<"$state")" == "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" ]]
}

cfip_adaptive_effective_mode() {
    [[ "$CFIP_ADAPTIVE_MEASUREMENT_ENABLED" == true && "$CFIP_ADAPTIVE_MEASUREMENT_MODE" != off ]] || { printf off; return; }
    if [[ "$CFIP_ADAPTIVE_MEASUREMENT_MODE" == guarded ]]; then
        if cfip_adaptive_qualification_is_usable; then
            printf guarded
            return
        fi
        local state fresh now max
        state="$(cfip_adaptive_state_json)"; fresh="$(jq -r '.freshAt // 0' <<<"$state")"; now="$CFIP_ADAPTIVE_NOW"; max="$CFIP_ADAPTIVE_EVALUATION_MAX_AGE_SECONDS"
        if [[ "$(jq -r '.qualificationState // ""' <<<"$state")" == qualified && "$fresh" =~ ^[0-9]+$ && "$max" =~ ^[1-9][0-9]*$ ]] && ((now-fresh > max)); then
            jq --argjson now "$now" '.+{qualificationState:"stale",qualificationReason:"evidence_stale",lastFallbackReason:"evidence_stale",updatedAt:$now}' <<<"$state" | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
        fi
    fi
    printf shadow
}

cfip_adaptive_prepare_probe_input() {
    local input="$1" output="$2" plan="$3" effective
    effective="$(cfip_adaptive_effective_mode)"; CFIP_ADAPTIVE_EFFECTIVE_MODE="$effective"
    if [[ "$effective" != guarded ]]; then
        cfip_adaptive_write_plan "$input" "$plan" || return 1
        cat "$input" | cfip_atomic_write "$output"
        return 0
    fi
    cfip_adaptive_write_plan "$input" "$plan" || return 1
    jq -c '.selectedIps as $ips|[.candidates[]|select((.ip as $ip|$ips|index($ip))!=null)]' "$plan" | cfip_atomic_write "$output"
}

cfip_adaptive_note_run() {
    local state count interval due now context last_context
    state="$(cfip_adaptive_state_json)"; count="$(jq -r '.runCount // 0' <<<"$state")"; interval="$CFIP_ADAPTIVE_AUDIT_INTERVAL"; now="$CFIP_ADAPTIVE_NOW"; context="$CFIP_ADAPTIVE_CONTEXT_FINGERPRINT"; last_context="$(jq -r '.lastContextFingerprint // empty' <<<"$state")"
    if [[ -n "$last_context" && "$last_context" != "$context" ]]; then count=0; fi
    [[ "$count" =~ ^[0-9]+$ ]] || count=0; [[ "$interval" =~ ^[1-9][0-9]*$ ]] || interval=20
    count=$((count+1)); due=false; ((count % interval == 0)) && due=true
    jq --argjson count "$count" --argjson now "$now" --argjson due "$due" --arg run "$CFIP_RUN_ID" --arg context "$context" '.+{runCount:$count,lastRunId:$run,lastAuditDue:$due,lastContextFingerprint:$context,updatedAt:$now}' <<<"$state" | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
    [[ "$due" == true ]]
}

cfip_adaptive_make_audit_record() {
    local plan="$1" native="$2" full="$3" output="$4" candidate_count actual_count winner topn selected k inside top_inside quality severe insuff savings k25 k40 k60
    [[ -s "$plan" && -s "$native" && -s "$full" ]] || return 1
    candidate_count="$(jq -r '.candidateCount // 0' "$plan")"; actual_count="$(jq 'length' "$full")"; winner="$(jq -r '.[0].ip // empty' "$native")"; topn="$(jq -c '.[0:3]|map(.ip)' "$native")"; selected="$(jq -c '.selectedIps // []' "$plan")"; k="$(jq -r '.selectedK // 0' "$plan")"
    [[ "$candidate_count" =~ ^[1-9][0-9]*$ && "$actual_count" == "$candidate_count" && -n "$winner" ]] || return 1
    inside=false; jq -e --arg winner "$winner" '.[]|select(.==$winner)' <<<"$selected" >/dev/null 2>&1 && inside=true
    top_inside="$(jq -nr --argjson top "$topn" --argjson selected "$selected" '([$top[]|select($selected|index(.))]|length) / ([$top[]]|length)')"
    k25="$(jq -nr --argjson order "$(jq -c '.adaptiveOrder' "$plan")" --arg winner "$winner" --argjson top "$topn" --argjson n "$candidate_count" 'def metric($pct): (((($n*$pct+99)/100)|floor) as $raw|if $raw<1 then 1 else $raw end) as $k|($order[0:$k]) as $p|{selectedK:$k,winnerRecall:(if ($p|index($winner)) then 1 else 0 end),topNRecall:(if ($top|length)==0 then 0 else ([$top[]|select($p|index(.))]|length)/($top|length) end)}; metric(25)')"
    k40="$(jq -nr --argjson order "$(jq -c '.adaptiveOrder' "$plan")" --arg winner "$winner" --argjson top "$topn" --argjson n "$candidate_count" 'def metric($pct): (((($n*$pct+99)/100)|floor) as $raw|if $raw<1 then 1 else $raw end) as $k|($order[0:$k]) as $p|{selectedK:$k,winnerRecall:(if ($p|index($winner)) then 1 else 0 end),topNRecall:(if ($top|length)==0 then 0 else ([$top[]|select($p|index(.))]|length)/($top|length) end)}; metric(40)')"
    k60="$(jq -nr --argjson order "$(jq -c '.adaptiveOrder' "$plan")" --arg winner "$winner" --argjson top "$topn" --argjson n "$candidate_count" 'def metric($pct): (((($n*$pct+99)/100)|floor) as $raw|if $raw<1 then 1 else $raw end) as $k|($order[0:$k]) as $p|{selectedK:$k,winnerRecall:(if ($p|index($winner)) then 1 else 0 end),topNRecall:(if ($top|length)==0 then 0 else ([$top[]|select($p|index(.))]|length)/($top|length) end)}; metric(60)')"
    quality=0; [[ "$inside" == true ]] || quality=1
    severe=0; [[ "$inside" == true ]] || severe=1
    insuff="$(jq -nr --argjson n "$candidate_count" --argjson full "$(cat "$full")" 'if $n==0 then 1 else (1-(([$full[]|select(.eligible==true)]|length)/$n)) end')"
    savings="$(jq -nr --argjson n "$candidate_count" --argjson k "$k" 'if $n==0 then 0 else 1-($k/$n) end')"
    jq -cn --arg runId "$CFIP_RUN_ID" --arg fp "$CFIP_ADAPTIVE_CONTEXT_FINGERPRINT" --argjson at "$CFIP_ADAPTIVE_NOW" --argjson count "$candidate_count" --argjson actual "$actual_count" --argjson baseline "$(jq -c '.baselineOrder' "$plan")" --argjson cfst "$(jq -c '.cfstOrder' "$plan")" --argjson adaptive "$(jq -c '.adaptiveOrder' "$plan")" --argjson selected "$selected" --arg winner "$winner" --argjson topn "$topn" --argjson k "$k" --argjson inside "$inside" --argjson topInside "$top_inside" --argjson quality "$quality" --argjson severe "$severe" --argjson insuff "$insuff" --argjson savings "$savings" --argjson scheduler "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson contract "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" \
      --argjson k25 "$k25" --argjson k40 "$k40" --argjson k60 "$k60" \
      '{schemaVersion:1,fullAudit:true,runId:$runId,at:$at,contextFingerprint:$fp,candidateCount:$count,actualProbeCount:$actual,baselineOrder:$baseline,cfstOrder:$cfst,adaptiveOrder:$adaptive,appliedCandidates:$selected,fullNativeWinner:$winner,fullNativeTopN:$topn,selectedK:$k,bestCandidateWithinK:$inside,winnerRecall:(if $inside then 1 else 0 end),topNRecall:$topInside,appliedCandidateRecall:(if $inside then 1 else 0 end),qualityDeltaToFullWinner:$quality,severeMiss:$severe,eligibleInsufficiencyRate:$insuff,probeSavings:$savings,K25:$k25,K40:$k40,K60:$k60,schedulerVersion:$scheduler,featureContractVersion:$contract}' | cfip_atomic_write "$output"
}

cfip_adaptive_safe_count() {
    jq '[.[]|select(.eligible==true and ((.probeSummary.totalMs // 1e18)<=5000) and ((.probeSummary.ttfbMs // 1e18)<=3000) and ((.probeSummary.lossRate // .lossRate // 1)<=0.25))]|length' "$1"
}

cfip_adaptive_update_runtime() {
    local reason="$1" selected="$2" expansion="$3" state
    state="$(cfip_adaptive_state_json)"
    jq --arg reason "$reason" --argjson selected "$selected" --argjson expansion "$expansion" '.+{lastFallbackReason:(if $reason=="" then null else $reason end),selectedK:$selected,lastExpansionCount:$expansion,updatedAt:(now|floor)}' <<<"$state" | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
}

cfip_adaptive_probe() {
    local input="$1" output="$2" domains="$3" timeout="$4" required="$5" batch_size="$6" max_count="$7" plan="$8" metrics="$9" effective="${10}"
    local selected remaining batch result probed='[]' selected_count=0 take fallback=false
    if [[ "$effective" != guarded ]]; then
        cfip_probe_candidates_batched "$input" "$output" "$domains" "$timeout" "$required" "$batch_size" "${CFIP_MAX_PROBE_COUNT:-$max_count}"
        return $?
    fi
    [[ -s "$plan" ]] || fallback=true
    if [[ "$fallback" == false ]]; then
        selected="$(jq -c '.selectedIps as $ips|[.candidates[]|select((.ip as $ip|$ips|index($ip))!=null)]' "$plan")"
        result="$(mktemp /tmp/cfip-adaptive-probed.XXXXXX)" || return 1
        printf '%s\n' "$selected" | cfip_probe_candidates - "$result" "$domains" "$timeout" 2>/dev/null || fallback=true
        [[ "$fallback" == true ]] || probed="$(cat "$result" 2>/dev/null || printf '[]')"
        rm -f "$result"; selected_count="$(jq 'length' <<<"$probed")"
        while [[ "$fallback" == false ]] && (( $(cfip_adaptive_safe_count <(printf '%s\n' "$probed")) < required )) && ((selected_count < max_count)); do
            remaining="$(jq -c '.remainingCandidates' "$plan")"
            [[ "$(jq 'length' <<<"$remaining")" -gt 0 ]] || break
            take="$batch_size"; ((selected_count+take > max_count)) && take=$((max_count-selected_count))
            ((take > 0)) || break
            batch="$(jq --argjson n "$take" '.[0:$n]' <<<"$remaining")"
            result="$(mktemp /tmp/cfip-adaptive-expand.XXXXXX)" || { fallback=true; break; }
            printf '%s\n' "$batch" | cfip_probe_candidates - "$result" "$domains" "$timeout" 2>/dev/null || fallback=true
            [[ "$fallback" == true ]] || probed="$(jq -cn --argjson a "$probed" --argjson b "$(cat "$result" 2>/dev/null || printf '[]')" '$a+$b')"
            rm -f "$result"; selected_count="$(jq 'length' <<<"$probed")"
        done
        (( $(cfip_adaptive_safe_count <(printf '%s\n' "$probed")) >= required )) || fallback=true
    fi
    if [[ "$fallback" == true ]]; then
        cfip_probe_candidates_batched "$input" "$output" "$domains" "$timeout" "$required" "$batch_size" "$max_count" || return $?
        cfip_adaptive_update_runtime "unqualified_or_probe_error" 0 0
        [[ -n "$metrics" ]] && jq -cn '{adaptiveFallback:true,reason:"unqualified_or_probe_error"}' | cfip_atomic_write "$metrics"
        return 0
    fi
    printf '%s\n' "$probed" | cfip_atomic_write "$output"
    cfip_adaptive_update_runtime "" "$(jq '.selectedK' "$plan")" "$((selected_count > required ? 1 : 0))"
    [[ -n "$metrics" ]] && jq -cn --argjson selected "$(jq '.selectedK' "$plan")" --argjson probed "$selected_count" '{adaptiveSelectedK:$selected,adaptiveProbed:$probed,adaptiveFallback:false}' | cfip_atomic_write "$metrics"
}

cfip_adaptive_status_json() {
    local state evidence
    state="$(cfip_adaptive_state_json)"; evidence="$(cfip_adaptive_evidence_json)"
    jq -cn --argjson state "$state" --argjson evidence "$evidence" --arg requested "$CFIP_ADAPTIVE_MEASUREMENT_MODE" --arg effective "$(cfip_adaptive_effective_mode)" \
      '$state+{requestedMode:$requested,effectiveMode:$effective,evidenceWindowSize:($evidence|length),evidenceFreshAt:([$evidence[]|.at]|max // null),available:true,partition:"native-adaptive-measurement"}'
}

cfip_adaptive_record_audit() {
    local record="$1" current next state context min window count healthy negative now
    jq -e 'type=="object" and .fullAudit==true and (.winnerRecall|type)=="number" and (.topNRecall|type)=="number" and (.severeMiss|type)=="number" and (.eligibleInsufficiencyRate|type)=="number" and (.probeSavings|type)=="number"' "$record" >/dev/null 2>&1 || return 1
    current="$(cfip_adaptive_evidence_json)"; next="$(jq -n --argjson current "$current" --argjson item "$(cat "$record")" --argjson limit "$CFIP_ADAPTIVE_EVIDENCE_LIMIT" '$current+[$item]|.[-$limit:]')"
    printf '%s\n' "$next" | cfip_atomic_write "$CFIP_ADAPTIVE_EVIDENCE_FILE" || return 1
    context="$(jq -r '.contextFingerprint // empty' "$record")"; min="$CFIP_ADAPTIVE_MIN_EVIDENCE"; window="$CFIP_ADAPTIVE_EVIDENCE_WINDOW"; now="$CFIP_ADAPTIVE_NOW"; state="$(cfip_adaptive_state_json)"
    count="$(jq --argjson e "$next" --arg ctx "$context" --argjson s "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson c "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" --argjson w "$window" '[$e[]|select(.contextFingerprint==$ctx and .schedulerVersion==$s and .featureContractVersion==$c)][-$w:]|length' <<<"$state")"
    healthy="$(jq --argjson e "$next" --arg ctx "$context" --argjson s "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson c "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" --argjson min "$min" --argjson w "$window" '[$e[]|select(.contextFingerprint==$ctx and .schedulerVersion==$s and .featureContractVersion==$c)][-$w:] as $v|if ($v|length)<$min then false else (([$v[].winnerRecall]|add/length)>=0.98 and ([$v[].topNRecall]|add/length)>=0.95 and ([$v[].severeMiss]|add/length)<=0.01 and ([$v[].eligibleInsufficiencyRate]|add/length)<=0.01 and ([$v[].probeSavings]|add/length)>=0.20) end' <<<"$state")"
    negative="$(jq --argjson e "$next" --arg ctx "$context" --argjson s "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson c "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" --argjson w "$window" '[$e[]|select(.contextFingerprint==$ctx and .schedulerVersion==$s and .featureContractVersion==$c)][-$w:]|if length==0 then false else ((map(.severeMiss)|add/length)>0.05 or (map(.winnerRecall)|add/length)<0.90) end' <<<"$state")"
    if [[ "$healthy" == true ]]; then state="$(jq --argjson count "$count" --arg ctx "$context" --argjson now "$now" '.+{qualificationState:"qualified",qualificationReason:"thresholds_met",evidenceCount:$count,freshAt:$now,contextFingerprint:$ctx}' <<<"$state")"
    elif [[ "$negative" == true ]]; then state="$(jq --argjson count "$count" --argjson now "$now" '.+{qualificationState:"insufficient",qualificationReason:"negative_evidence",evidenceCount:$count,freshAt:$now}' <<<"$state")"
    else state="$(jq --argjson count "$count" --argjson now "$now" '.+{qualificationState:"insufficient",qualificationReason:"insufficient_evidence",evidenceCount:$count,freshAt:$now}' <<<"$state")"; fi
    state="$(jq --argjson now "$now" '.+{auditSequence:(.auditSequence+1),lastAuditAt:$now,updatedAt:$now}' <<<"$state")"
    printf '%s\n' "$state" | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
}
