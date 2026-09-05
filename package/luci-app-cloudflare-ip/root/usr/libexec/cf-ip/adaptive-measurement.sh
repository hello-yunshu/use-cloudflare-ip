#!/usr/bin/env bash
# Native adaptive measurement. It schedules probes only and never creates a
# Runtime/Rill learner or partition.
# shellcheck shell=bash

CFIP_ADAPTIVE_SCHEDULER_VERSION="${CFIP_ADAPTIVE_SCHEDULER_VERSION:-1}"
CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION="${CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION:-1}"
CFIP_ADAPTIVE_STATE_FILE="$CFIP_STATUS_DIR/adaptive-measurement-state.json"
CFIP_ADAPTIVE_EVIDENCE_FILE="$CFIP_STATUS_DIR/adaptive-measurement-evidence.json"
CFIP_ADAPTIVE_EVIDENCE_LIMIT="${CFIP_ADAPTIVE_EVIDENCE_LIMIT:-100}"
CFIP_ADAPTIVE_EVIDENCE_MAX_BYTES="${CFIP_ADAPTIVE_EVIDENCE_MAX_BYTES:-524288}"
CFIP_ADAPTIVE_RUN_SEQUENCE=0

cfip_adaptive_default_state_json() {
    jq -cn --argjson scheduler "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson contract "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" \
      '{schemaVersion:1,requestedMode:"shadow",effectiveMode:"shadow",qualificationState:"insufficient",qualificationReason:"no_eligible_audit_evidence",evidenceCount:0,freshAt:null,contextFingerprint:null,lastContextFingerprint:null,schedulerVersion:$scheduler,featureContractVersion:$contract,targetRatioPercent:25,minProbeCount:8,explorationRatioPercent:10,selectedK:0,lastRunId:null,runCount:0,auditSequence:0,lastAuditAt:null,lastAuditDue:false,lastFallbackReason:null,lastExpansionCount:0,updatedAt:(now|floor)}'
}

cfip_adaptive_state_json() {
    if [[ -s "$CFIP_ADAPTIVE_STATE_FILE" ]] && jq -e 'type=="object" and .schemaVersion==1' "$CFIP_ADAPTIVE_STATE_FILE" >/dev/null 2>&1; then
        cat "$CFIP_ADAPTIVE_STATE_FILE"
    else
        cfip_adaptive_default_state_json
    fi
}

cfip_adaptive_evidence_json() {
    local bytes=0
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

# Add the declared history/source names before the scheduler sees a candidate.
# Probe outcomes are deliberately not read here; the scheduler is pre-probe.
cfip_adaptive_enrich_preprobe() {
    local input="$1" output="$2" history='{}' prefix_history='{}' colo_history='{}' now
    [[ -s "$input" ]] || { printf '[]\n' | cfip_atomic_write "$output"; return 0; }
    declare -F cfip_rill_history_json >/dev/null 2>&1 && history="$(cfip_rill_history_json)"
    declare -F cfip_rill_prefix_history_json >/dev/null 2>&1 && prefix_history="$(cfip_rill_prefix_history_json)"
    declare -F cfip_rill_colo_history_json >/dev/null 2>&1 && colo_history="$(cfip_rill_colo_history_json)"
    now="$(date +%s)"
    jq --argjson history "$history" --argjson prefixHistory "$prefix_history" --argjson coloHistory "$colo_history" --argjson now "$now" '
      map(. as $candidate |
        ($history[($candidate.ip|tostring)] // {}) as $h |
        ($prefixHistory[($candidate.prefixKey // "")] // {}) as $p |
        ($coloHistory.entries[(($candidate.colo // "")|tostring)] // {}) as $co |
        . + {
          historyMedianTotalMs:($h.medianTotalMs // null),
          historyP95TotalMs:($h.p95TotalMs // null),
          historyEWMA:($h.ewmaTotalMs // null),
          historyConsecutiveFailures:($h.consecutiveFailures // 0),
          historyLastSeen:($h.lastSeen // 0),
          prefixHistory:($p|if type=="object" and ((.samples//0)>0) then {samples:(.samples//0),successRate:(.successRate//0.5),p95TotalMs:(.p95TotalMs//null),lastSeen:(.lastSeen//0),consecutiveFailures:(.consecutiveFailures//0)} else null end),
          coloHistory:($co|if type=="object" and ((.samples//0)>0) then {samples:(.samples//0),successRate:(.successRate//0.5),lastSeen:(.lastSeen//0)} else null end),
          previousWinner:($h.lastSelected == true)
        })
    ' "$input" | cfip_atomic_write "$output"
}

cfip_adaptive_orders_json() {
    local input="$1"
    [[ -s "$input" ]] || return 1
    jq -cn --argjson scheduler "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson contract "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" --slurpfile source "$input" '
      ($source[0] | if type=="array" then . else [] end) as $candidates |
      ($candidates|map({candidateId:(.candidateId // ("cfst:" + (.ip|tostring))),ip:(.ip|tostring),family:(.family // "unknown"),cfstRank:(.cfstRank // 999999),sourceCount:(.sourceCount // 0),sources:(.sources // []),origin:(.origin // "unknown"),sourceStale:(.sourceStale // false),sourceReliability:(.sourceReliability // 0.5),historyMedianTotalMs:(.historyMedianTotalMs // null),historyP95TotalMs:(.historyP95TotalMs // null),historyEWMA:(.historyEWMA // null),historyConsecutiveFailures:(.historyConsecutiveFailures // 0),historyLastSeen:(.historyLastSeen // 0),prefixHistory:(.prefixHistory // null),coloHistory:(.coloHistory // null),previousWinner:(.previousWinner // false)})) as $raw |
      (reduce $raw[] as $candidate ([]; if any(.[]; .ip==$candidate.ip) then . else .+[$candidate] end)) as $c |
      ($c|sort_by(.cfstRank,.ip)) as $cfst |
      ($c|map(. + {adaptiveScore:((1000000/(1+(.cfstRank|tonumber))) + ((.sourceReliability|tonumber)*10000) + (if .sourceStale then 0 else 500 end) + (if .previousWinner then 20000 else 0 end) - ((.historyConsecutiveFailures|tonumber)*1000))})) as $scored |
      ($scored|sort_by(-.adaptiveScore,.cfstRank,.ip)) as $adaptive |
      {schemaVersion:1,schedulerVersion:$scheduler,featureContractVersion:$contract,candidateCount:($c|length),baselineOrder:($c|map(.ip)),cfstOrder:($cfst|map(.ip)),adaptiveOrder:($adaptive|map(.ip)),candidates:$c,scoredCandidates:$adaptive}'
}

cfip_adaptive_write_plan() {
    local input="$1" output="$2" orders candidates n ratio min max explore_ratio explore_count k selected remaining anchors anchor previous family ip
    local tail exploration ranked_fill seed hash rotation run_sequence candidates_file orders_file selected_file remaining_file anchors_file exploration_file ranked_file
    orders="$(cfip_adaptive_orders_json "$input")" || return 1
    candidates="$(jq -c '.candidates' <<<"$orders")"; n="$(jq 'length' <<<"$candidates")"
    ratio="${CFIP_ADAPTIVE_TARGET_RATIO_PERCENT:-25}"; min="${CFIP_ADAPTIVE_MIN_PROBE_COUNT:-8}"; max="${CFIP_ADAPTIVE_MAX_PROBE_COUNT:-60}"; explore_ratio="${CFIP_ADAPTIVE_EXPLORATION_RATIO_PERCENT:-10}"
    [[ "$ratio" =~ ^[0-9]+$ ]] || ratio=25; [[ "$min" =~ ^[1-9][0-9]*$ ]] || min=8; [[ "$max" =~ ^[1-9][0-9]*$ ]] || max=60; [[ "$explore_ratio" =~ ^[0-9]+$ ]] || explore_ratio=10
    k="$(jq -nr --argjson n "$n" --argjson ratio "$ratio" --argjson min "$min" --argjson max "$max" --argjson required "${CFIP_IP_COUNT:-1}" '([$required,(($n*$ratio+99)/100|floor),$min]|max) as $v|[$v,$n,$max]|min')"
    ((k < ${CFIP_IP_COUNT:-1})) && k="${CFIP_IP_COUNT:-1}"; ((k > n)) && k="$n"
    anchors='[]'
    previous="$(jq -r '.scoredCandidates[]|select(.previousWinner==true)|.ip' <<<"$orders" | head -n1)"
    [[ -n "$previous" ]] && anchors="$(jq -cn --argjson a "$anchors" --arg ip "$previous" 'reduce ($a+[$ip])[] as $v ([];if index($v) then . else .+[$v] end)')"
    if [[ "${CFIP_IP_TYPE:-ipv4}" == both ]]; then
        for family in ipv4 ipv6; do
            ip="$(jq -r --arg family "$family" '.scoredCandidates[]|select(.family==$family)|.ip' <<<"$orders" | head -n1)"
            [[ -n "$ip" ]] && anchors="$(jq -cn --argjson a "$anchors" --arg ip "$ip" 'reduce ($a+[$ip])[] as $v ([];if index($v) then . else .+[$v] end)')"
        done
    fi
    while IFS= read -r source; do
        [[ -n "$source" ]] || continue
        ip="$(jq -r --arg source "$source" '.scoredCandidates[]|select((.sources|index($source))!=null)|.ip' <<<"$orders" | head -n1)"
        [[ -n "$ip" ]] && anchors="$(jq -cn --argjson a "$anchors" --arg ip "$ip" 'reduce ($a+[$ip])[] as $v ([];if index($v) then . else .+[$v] end)')"
    done < <(jq -r '.scoredCandidates[].sources[]?' <<<"$orders" | sort -u)
    for feature in prefixHistory coloHistory; do
        while IFS= read -r value; do
            [[ -n "$value" && "$value" != null ]] || continue
            ip="$(jq -r --arg feature "$feature" --arg value "$value" '.scoredCandidates[]|select((.[ $feature ]|tostring)==$value)|.ip' <<<"$orders" | head -n1)"
            [[ -n "$ip" ]] && anchors="$(jq -cn --argjson a "$anchors" --arg ip "$ip" 'reduce ($a+[$ip])[] as $v ([];if index($v) then . else .+[$v] end)')"
        done < <(jq -r --arg feature "$feature" '.scoredCandidates[]|select(.[ $feature ]!=null)|.[ $feature ]|tostring' <<<"$orders" | sort -u)
    done
    anchor="$(jq -r '.baselineOrder[0] // empty' <<<"$orders")"
    [[ -n "$anchor" ]] && anchors="$(jq -cn --argjson a "$anchors" --arg ip "$anchor" 'reduce ($a+[$ip])[] as $v ([];if index($v) then . else .+[$v] end)')"
    run_sequence="${CFIP_ADAPTIVE_RUN_SEQUENCE:-0}"; [[ "$run_sequence" =~ ^[0-9]+$ ]] || run_sequence=0
    seed="${CFIP_ADAPTIVE_CONTEXT_FINGERPRINT:-none}:$run_sequence"
    hash="$(printf '%s' "$seed" | sha256sum | cut -c1-8)"; rotation=$((16#$hash))
    explore_count=$((k*explore_ratio/100)); tail="$(jq -c '.adaptiveOrder|reverse' <<<"$orders")"
    exploration="$(jq -cn --argjson tail "$tail" --argjson anchors "$anchors" --argjson e "$explore_count" --argjson offset "$rotation" '
      [$tail[] as $ip | select(($anchors|index($ip)) == null) | $ip] as $pool |
      if ($pool|length)==0 or $e==0 then [] else [range(0; ([$e,($pool|length)]|min)) as $i | $pool[(($offset+$i)%($pool|length))]] end')"
    ranked_fill="$(jq -cn --argjson order "$(jq -c '.adaptiveOrder' <<<"$orders")" --argjson anchors "$anchors" --argjson exploration "$exploration" '[$order[] as $ip | select(($anchors|index($ip)) == null and ($exploration|index($ip)) == null) | $ip]')"
    selected="$(jq -cn --argjson a "$anchors" --argjson e "$exploration" --argjson r "$ranked_fill" --argjson k "$k" 'reduce ($a+$e+$r)[] as $ip ([];if index($ip) then . else .+[$ip] end)|.[0:$k]')"
    candidates_file="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-candidates.XXXXXX")" || return 1
    printf '%s\n' "$candidates" >"$candidates_file"
    remaining="$(jq -cn --slurpfile c "$candidates_file" --argjson selected "$selected" '$c[0]|map(select((.ip as $ip|$selected|index($ip))==null))')" || { rm -f "$candidates_file"; return 1; }
    orders_file="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-orders.XXXXXX")" || { rm -f "$candidates_file"; return 1; }
    selected_file="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-selected.XXXXXX")" || { rm -f "$candidates_file" "$orders_file"; return 1; }
    remaining_file="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-remaining.XXXXXX")" || { rm -f "$candidates_file" "$orders_file" "$selected_file"; return 1; }
    anchors_file="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-anchors.XXXXXX")" || { rm -f "$candidates_file" "$orders_file" "$selected_file" "$remaining_file"; return 1; }
    exploration_file="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-exploration.XXXXXX")" || { rm -f "$candidates_file" "$orders_file" "$selected_file" "$remaining_file" "$anchors_file"; return 1; }
    ranked_file="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-ranked.XXXXXX")" || { rm -f "$candidates_file" "$orders_file" "$selected_file" "$remaining_file" "$anchors_file" "$exploration_file"; return 1; }
    printf '%s\n' "$orders" >"$orders_file"; printf '%s\n' "$selected" >"$selected_file"; printf '%s\n' "$remaining" >"$remaining_file"; printf '%s\n' "$anchors" >"$anchors_file"; printf '%s\n' "$exploration" >"$exploration_file"; printf '%s\n' "$ranked_fill" >"$ranked_file"
    jq -cn --slurpfile orders "$orders_file" --slurpfile selected "$selected_file" --slurpfile remaining "$remaining_file" --slurpfile anchors "$anchors_file" --slurpfile exploration "$exploration_file" --slurpfile ranked "$ranked_file" --argjson k "$k" --argjson offset "$rotation" --argjson run "$run_sequence" --arg mode "${CFIP_ADAPTIVE_EFFECTIVE_MODE:-shadow}" --argjson ratio "$ratio" --argjson min "$min" --argjson max "$max" \
      '$orders[0]+{selectedK:$k,selectedIps:$selected[0],remainingCandidates:$remaining[0],mandatoryAnchorIps:$anchors[0],explorationIps:$exploration[0],rankedFillIps:$ranked[0],explorationOffset:$offset,runSequence:$run,effectiveMode:$mode,targetRatioPercent:$ratio,minProbeCount:$min,maxProbeCount:$max,mandatoryAnchors:$anchors[0]}' | cfip_atomic_write "$output"
    rm -f "$candidates_file" "$orders_file" "$selected_file" "$remaining_file" "$anchors_file" "$exploration_file" "$ranked_file"
}

cfip_adaptive_qualification_is_usable() {
    local state fresh now max context
    state="$(cfip_adaptive_state_json)"
    [[ "$(jq -r '.qualificationState // "insufficient"' <<<"$state")" == qualified ]] || return 1
    fresh="$(jq -r '.freshAt // 0' <<<"$state")"; now="${CFIP_ADAPTIVE_NOW:-$(date +%s)}"; max="${CFIP_ADAPTIVE_EVALUATION_MAX_AGE_SECONDS:-604800}"
    [[ "$fresh" =~ ^[0-9]+$ && "$max" =~ ^[1-9][0-9]*$ ]] || return 1; ((now-fresh <= max)) || return 1
    context="$CFIP_ADAPTIVE_CONTEXT_FINGERPRINT"
    [[ -z "$context" || "$context" == "$(jq -r '.contextFingerprint // ""' <<<"$state")" ]] || return 1
    [[ "$(jq -r '.schedulerVersion // 0' <<<"$state")" == "$CFIP_ADAPTIVE_SCHEDULER_VERSION" && "$(jq -r '.featureContractVersion // 0' <<<"$state")" == "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" ]]
}

cfip_adaptive_effective_mode() {
    [[ "${CFIP_ADAPTIVE_MEASUREMENT_ENABLED:-false}" == true && "${CFIP_ADAPTIVE_MEASUREMENT_MODE:-off}" != off ]] || { printf off; return; }
    if [[ "$CFIP_ADAPTIVE_MEASUREMENT_MODE" == guarded ]]; then
        if cfip_adaptive_qualification_is_usable; then printf guarded; return; fi
        local state fresh now max
        state="$(cfip_adaptive_state_json)"; fresh="$(jq -r '.freshAt // 0' <<<"$state")"; now="${CFIP_ADAPTIVE_NOW:-$(date +%s)}"; max="${CFIP_ADAPTIVE_EVALUATION_MAX_AGE_SECONDS:-604800}"
        if [[ "$(jq -r '.qualificationState // ""' <<<"$state")" == qualified && "$fresh" =~ ^[0-9]+$ && "$max" =~ ^[1-9][0-9]*$ ]] && ((now-fresh > max)); then
            jq --argjson now "$now" '.+{qualificationState:"stale",qualificationReason:"evidence_stale",lastFallbackReason:"evidence_stale",updatedAt:$now}' <<<"$state" | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
        fi
    fi
    printf shadow
}

cfip_adaptive_prepare_probe_input() {
    local input="$1" output="$2" plan="$3" enriched effective
    effective="$(cfip_adaptive_effective_mode)"; CFIP_ADAPTIVE_EFFECTIVE_MODE="$effective"
    enriched="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-enriched.XXXXXX")" || return 1
    cfip_adaptive_enrich_preprobe "$input" "$enriched" || { rm -f "$enriched"; return 1; }
    cfip_adaptive_write_plan "$enriched" "$plan" || { rm -f "$enriched"; return 1; }
    rm -f "$enriched"
    if [[ "$effective" != guarded ]]; then cat "$input" | cfip_atomic_write "$output"; return $?; fi
    jq -c '.selectedIps as $ips|[.candidates[]|select((.ip as $ip|$ips|index($ip))!=null)]' "$plan" | cfip_atomic_write "$output"
}

cfip_adaptive_note_run() {
    local state count interval due now context last_context
    state="$(cfip_adaptive_state_json)"; count="$(jq -r '.runCount // 0' <<<"$state")"; interval="${CFIP_ADAPTIVE_AUDIT_INTERVAL:-20}"; now="${CFIP_ADAPTIVE_NOW:-$(date +%s)}"; context="${CFIP_ADAPTIVE_CONTEXT_FINGERPRINT:-}"; last_context="$(jq -r '.lastContextFingerprint // empty' <<<"$state")"
    if [[ -n "$last_context" && "$last_context" != "$context" ]]; then count=0; fi
    [[ "$count" =~ ^[0-9]+$ ]] || count=0; [[ "$interval" =~ ^[1-9][0-9]*$ ]] || interval=20
    count=$((count+1)); CFIP_ADAPTIVE_RUN_SEQUENCE="$count"; due=false; ((count % interval == 0)) && due=true
    jq --argjson count "$count" --argjson now "$now" --argjson due "$due" --arg run "${CFIP_RUN_ID:-}" --arg context "$context" '.+{runCount:$count,lastRunId:$run,lastAuditDue:$due,lastContextFingerprint:$context,updatedAt:$now}' <<<"$state" | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
    [[ "$due" == true ]]
}

cfip_adaptive_unique_json() {
    jq 'reduce .[] as $candidate ([]; if any(.[]; .ip == $candidate.ip) then . else .+[$candidate] end)'
}

cfip_adaptive_make_audit_record() {
    local plan="$1" native="$2" full="$3" output="$4" probe_rc="${5:-0}"
    local candidate_count actual_count unique_count winner topn planned candidate_ips probed_ips production_probed production_selected k inside top_inside quality severe insuff savings subset_safe_count k25 k40 k60 audit_complete audit_censored censor_reason full_json native_json metrics='{}'
    [[ -s "$plan" ]] || return 1
    full_json='[]'; if [[ -s "$full" ]] && jq -e 'type=="array"' "$full" >/dev/null 2>&1; then full_json="$(<"$full")"; else probe_rc=1; fi
    native_json='[]'; if [[ -s "$native" ]] && jq -e 'type=="array"' "$native" >/dev/null 2>&1; then native_json="$(<"$native")"; fi
    candidate_count="$(jq -r '.candidateCount // 0' "$plan")"; actual_count="$(jq 'length' <<<"$full_json")"; unique_count="$(cfip_adaptive_unique_json <<<"$full_json" | jq 'length')"
    candidate_ips="$(jq -c '(.candidates // [])|map(.ip)|unique|sort' "$plan")"; probed_ips="$(jq -c 'map(.ip)|unique|sort' <<<"$full_json")"
    winner="$(jq -r '.[0].ip // empty' <<<"$native_json" 2>/dev/null || true)"; topn="$(jq -c --argjson n "${CFIP_IP_COUNT:-3}" '.[0:$n]|map(.ip)' <<<"$native_json" 2>/dev/null || printf '[]')"
    planned="$(jq -c '.selectedIps // []' "$plan")"; k="$(jq -r '.selectedK // 0' "$plan")"
    audit_complete=false; censor_reason=""
    [[ "$probe_rc" == 0 ]] || censor_reason="probe_infrastructure"
    [[ "$candidate_count" =~ ^[1-9][0-9]*$ && "$actual_count" == "$candidate_count" && "$unique_count" == "$candidate_count" && "$candidate_ips" == "$probed_ips" ]] || censor_reason="${censor_reason:-missing_or_duplicate_candidate_result}"
    if [[ -z "$censor_reason" ]] && ! jq -e 'all(.[]; (.ip|type)=="string" and (.probes|type)=="array" and (.probeSummary|type)=="object" and (.probeSummary.probeCount == (.probes|length)) and all(.probes[]; (.errorClass // "") != "measurement_budget" and (.errorClass // "") != "probe_infrastructure" and (.errorClass // "") != "partial_batch"))' <<<"$full_json" >/dev/null 2>&1; then censor_reason="incomplete_probe_result"; fi
    [[ -z "$censor_reason" ]] && audit_complete=true; audit_censored=true; [[ "$audit_complete" == true ]] && audit_censored=false
    production_probed="$(jq -c 'map(.ip)' <<<"$full_json" 2>/dev/null || printf '[]')"
    production_selected="$(jq -c --argjson n "${CFIP_IP_COUNT:-3}" '.[0:$n]|map(.ip)' <<<"$native_json" 2>/dev/null || printf '[]')"
    [[ -s "${CFIP_PROBE_METRICS_FILE:-}" ]] && metrics="$(jq -c 'if type=="object" then . else {} end' "$CFIP_PROBE_METRICS_FILE" 2>/dev/null || printf '{}')"
    inside=false; [[ -n "$winner" ]] && jq -e --arg winner "$winner" '.[]|select(.==$winner)' <<<"$planned" >/dev/null 2>&1 && inside=true
    top_inside="$(jq -nr --argjson top "$topn" --argjson selected "$planned" 'if ($top|length)==0 then 0 else ([$top[] as $ip|select($selected|index($ip))]|length)/($top|length) end')"
    subset_safe_count="$(jq -nr --slurpfile full <(printf '%s\n' "$full_json") --argjson planned "$planned" '[ $full[0][] | select(.ip as $ip | ($planned|index($ip))) | select(.eligible==true and ((.probeSummary.totalMs // 1e18)<=5000) and ((.probeSummary.ttfbMs // 1e18)<=3000) and ((.probeSummary.lossRate // .lossRate // 1)<=0.25)) ] | unique_by(.ip) | length')"
    insuff=1; ((subset_safe_count >= ${CFIP_IP_COUNT:-1})) && insuff=0
    k25="$(jq -nr --argjson order "$(jq -c '.adaptiveOrder' "$plan")" --arg winner "$winner" --argjson top "$topn" --argjson n "$candidate_count" 'def metric($pct): (((($n*$pct+99)/100)|floor) as $raw|if $raw<1 then 1 else $raw end) as $k|($order[0:$k]) as $p|{selectedK:$k,winnerRecall:(if ($p|index($winner)) then 1 else 0 end),topNRecall:(if ($top|length)==0 then 0 else ([$top[] as $ip|select($p|index($ip))]|length)/($top|length) end)}; metric(25)')"
    k40="$(jq -nr --argjson order "$(jq -c '.adaptiveOrder' "$plan")" --arg winner "$winner" --argjson top "$topn" --argjson n "$candidate_count" 'def metric($pct): (((($n*$pct+99)/100)|floor) as $raw|if $raw<1 then 1 else $raw end) as $k|($order[0:$k]) as $p|{selectedK:$k,winnerRecall:(if ($p|index($winner)) then 1 else 0 end),topNRecall:(if ($top|length)==0 then 0 else ([$top[] as $ip|select($p|index($ip))]|length)/($top|length) end)}; metric(40)')"
    k60="$(jq -nr --argjson order "$(jq -c '.adaptiveOrder' "$plan")" --arg winner "$winner" --argjson top "$topn" --argjson n "$candidate_count" 'def metric($pct): (((($n*$pct+99)/100)|floor) as $raw|if $raw<1 then 1 else $raw end) as $k|($order[0:$k]) as $p|{selectedK:$k,winnerRecall:(if ($p|index($winner)) then 1 else 0 end),topNRecall:(if ($top|length)==0 then 0 else ([$top[] as $ip|select($p|index($ip))]|length)/($top|length) end)}; metric(60)')"
    quality=0; [[ "$inside" == true ]] || quality=1; severe="$quality"; savings=0; ((candidate_count > 0)) && savings="$(jq -nr --argjson n "$candidate_count" --argjson k "$k" '1-($k/$n)')"
    jq -cn --arg runId "${CFIP_RUN_ID:-}" --arg fp "${CFIP_ADAPTIVE_CONTEXT_FINGERPRINT:-}" --argjson at "${CFIP_ADAPTIVE_NOW:-0}" --argjson count "$candidate_count" --argjson actual "$actual_count" --argjson baseline "$(jq -c '.baselineOrder' "$plan")" --argjson cfst "$(jq -c '.cfstOrder' "$plan")" --argjson adaptive "$(jq -c '.adaptiveOrder' "$plan")" --argjson planned "$planned" --argjson probed "$production_probed" --argjson production "$production_selected" --argjson metrics "$metrics" --arg winner "$winner" --argjson topn "$topn" --argjson k "$k" --argjson inside "$inside" --argjson topInside "$top_inside" --argjson quality "$quality" --argjson severe "$severe" --argjson insuff "$insuff" --argjson subsetSafe "$subset_safe_count" --argjson savings "$savings" --argjson complete "$audit_complete" --argjson censored "$audit_censored" --arg censor "$censor_reason" --argjson scheduler "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson contract "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" --argjson k25 "$k25" --argjson k40 "$k40" --argjson k60 "$k60" \
      '{schemaVersion:1,fullAudit:true,auditRun:true,auditComplete:$complete,auditCensored:$censored,censorReason:(if $censor=="" then null else $censor end),runId:$runId,at:$at,contextFingerprint:$fp,candidateCount:$count,actualProbeCount:$actual,uniqueProbeCount:($probed|length),baselineOrder:$baseline,cfstOrder:$cfst,adaptiveOrder:$adaptive,adaptivePlannedCandidates:$planned,productionProbedCandidates:$probed,nativeSelectedCandidates:$production,productionSelectedCandidates:[],finalSelectedCandidates:[],appliedCandidates:[],transactionApplied:false,candidateDecisionMode:null,candidateAuthority:null,fullNativeWinner:(if $winner=="" then null else $winner end),fullNativeTopN:$topn,selectedK:$k,plannedK:$k,adaptivePlannedCandidateRecall:(if $inside then 1 else 0 end),bestCandidateWithinK:$inside,winnerRecall:(if $inside then 1 else 0 end),topNRecall:$topInside,appliedCandidateRecall:null,qualityDeltaToFullWinner:$quality,severeMiss:$severe,subsetSafeCount:$subsetSafe,eligibleInsufficiency:($insuff==1),eligibleInsufficiencyRate:$insuff,probeSavings:$savings,measurementDurationMs:($metrics.measurementDurationMs//null),schedulerDurationMs:($metrics.schedulerDurationMs//null),probeDurationMs:($metrics.probeDurationMs//null),fullCandidateCount:($metrics.fullCandidateCount//$count),actualUniqueProbeCount:($metrics.actualUniqueProbeCount//($probed|length)),expansionCount:($metrics.expansionCount//0),fallbackUsed:($metrics.fallbackUsed//false),effectiveAdaptiveMode:($metrics.effectiveAdaptiveMode//null),K25:$k25,K40:$k40,K60:$k60,schedulerVersion:$scheduler,featureContractVersion:$contract}' | cfip_atomic_write "$output"
}

cfip_adaptive_safe_count() {
    cfip_adaptive_unique_json | jq '[.[]|select(.eligible==true and ((.probeSummary.totalMs // 1e18)<=5000) and ((.probeSummary.ttfbMs // 1e18)<=3000) and ((.probeSummary.lossRate // .lossRate // 1)<=0.25))]|length'
}

cfip_adaptive_update_runtime() {
    local reason="$1" selected="$2" expansion="$3" state
    state="$(cfip_adaptive_state_json)"
    jq --arg reason "$reason" --argjson selected "$selected" --argjson expansion "$expansion" '.+{lastFallbackReason:(if $reason=="" then null else $reason end),selectedK:$selected,lastExpansionCount:$expansion,updatedAt:(now|floor)}' <<<"$state" | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
}

cfip_adaptive_record_run_metrics() {
    local plan="$1" probed="$2" output="${3:-${CFIP_PROBE_METRICS_FILE:-}}" current='{}' actual=0 full=0 planned=0 expansion=0 fallback=false
    [[ -n "$output" ]] || return 0
    [[ -s "$output" ]] && current="$(jq -c 'if type=="object" then . else {} end' "$output" 2>/dev/null || printf '{}')"
    [[ -s "$probed" ]] && actual="$(jq 'map(.ip)|unique|length' "$probed" 2>/dev/null || printf 0)"
    [[ -s "${CFIP_INPUT_POOL_FILE:-}" ]] && full="$(jq 'length' "$CFIP_INPUT_POOL_FILE" 2>/dev/null || printf 0)"
    [[ -s "$plan" ]] && planned="$(jq '.selectedK // 0' "$plan" 2>/dev/null || printf 0)"
    expansion="$(jq -r '.expansionCount // 0' <<<"$current" 2>/dev/null || printf 0)"
    fallback="$(jq -r '.adaptiveFallback // false' <<<"$current" 2>/dev/null || printf false)"
    jq -cn --argjson current "$current" --argjson actual "$actual" --argjson full "$full" --argjson planned "$planned" --argjson expansion "$expansion" --argjson fallback "$fallback" --arg mode "${CFIP_ADAPTIVE_EFFECTIVE_MODE:-off}" --arg candidate "${CFIP_RILL_MODE:-off}" --argjson audit "${CFIP_ADAPTIVE_AUDIT_DUE:-false}" --argjson measurement "${CFIP_MEASUREMENT_DURATION_MS:-0}" --argjson scheduler "${CFIP_ADAPTIVE_SCHEDULER_DURATION_MS:-0}" --argjson probe "${CFIP_ADAPTIVE_PROBE_DURATION_MS:-0}" \
      '$current + {schemaVersion:1,measurementDurationMs:$measurement,schedulerDurationMs:$scheduler,probeDurationMs:$probe,fullCandidateCount:$full,plannedK:$planned,actualUniqueProbeCount:$actual,expansionCount:$expansion,fallbackUsed:$fallback,auditRun:$audit,effectiveAdaptiveMode:$mode,effectiveCandidateMode:$candidate}' | cfip_atomic_write "$output"
}

cfip_adaptive_patch_final_selection() {
    local audit="$1" selected="$2" decision="$3" applied="${4:-false}" selected_json='[]' mode='native' authority='native'
    [[ -s "$audit" && -s "$selected" ]] || return 1
    selected_json="$(jq -c 'if type=="array" then . else [] end' "$selected" 2>/dev/null || printf '[]')"
    if [[ -s "$decision" ]]; then
        mode="$(jq -r '.effectiveMode // "native"' "$decision" 2>/dev/null || printf native)"
        [[ "$mode" == assisted ]] && authority=rill
    fi
    jq -cn --argjson audit "$(cat "$audit")" --argjson selected "$selected_json" --argjson applied "$applied" --arg mode "$mode" --arg authority "$authority" \
      '$audit + {productionSelectedCandidates:($selected|map(.ip)),finalSelectedCandidates:($selected|map(.ip)),appliedCandidates:(if $applied then ($selected|map(.ip)) else [] end),transactionApplied:$applied,candidateDecisionMode:$mode,candidateAuthority:$authority,appliedCandidateRecall:(if (($audit.fullNativeWinner // null) != null and (($selected|map(.ip))|index($audit.fullNativeWinner))) then 1 else 0 end)}' | cfip_atomic_write "$audit"
}

cfip_adaptive_probe() {
    local input="$1" output="$2" domains="$3" timeout="$4" required="$5" batch_size="$6" max_count="$7" plan="$8" metrics="$9" effective="${10}"
    local selected remaining batch result probed='[]' selected_count=0 take fallback=false expansion_count=0
    if [[ "$effective" != guarded ]]; then
        cfip_probe_candidates_batched "$input" "$output" "$domains" "$timeout" "$required" "$batch_size" "${CFIP_MAX_PROBE_COUNT:-$max_count}"
        return $?
    fi
    [[ -s "$plan" ]] || fallback=true
    if [[ "$fallback" == false ]]; then
        selected="$(jq -c '.selectedIps as $ips|[.candidates[]|select((.ip as $ip|$ips|index($ip))!=null)]' "$plan")"; remaining="$(jq -c '.remainingCandidates // []' "$plan")"
        result="$(mktemp /tmp/cfip-adaptive-probed.XXXXXX)" || return 1
        printf '%s\n' "$selected" | cfip_probe_candidates - "$result" "$domains" "$timeout" 2>/dev/null || fallback=true
        [[ "$fallback" == true ]] || probed="$(cfip_adaptive_unique_json <"$result")"
        rm -f "$result"; selected_count="$(jq 'length' <<<"$probed")"
        while [[ "$fallback" == false ]] && (( $(printf '%s\n' "$probed" | cfip_adaptive_safe_count) < required )) && ((selected_count < max_count)); do
            [[ "$(jq 'length' <<<"$remaining")" -gt 0 ]] || break
            take="$batch_size"; ((selected_count+take > max_count)) && take=$((max_count-selected_count)); ((take > 0)) || break
            batch="$(jq --argjson n "$take" '.[0:$n]' <<<"$remaining")"; remaining="$(jq --argjson n "$take" '.[ $n: ]' <<<"$remaining")"
            result="$(mktemp /tmp/cfip-adaptive-expand.XXXXXX)" || { fallback=true; break; }
            printf '%s\n' "$batch" | cfip_probe_candidates - "$result" "$domains" "$timeout" 2>/dev/null || fallback=true
            if [[ "$fallback" == false ]]; then probed="$(jq -cn --argjson a "$probed" --argjson b "$(cfip_adaptive_unique_json <"$result")" '$a+$b' | cfip_adaptive_unique_json)"; fi
            rm -f "$result"; selected_count="$(jq 'length' <<<"$probed")"; expansion_count=$((expansion_count+1))
        done
        (( $(printf '%s\n' "$probed" | cfip_adaptive_safe_count) >= required )) || fallback=true
    fi
    if [[ "$fallback" == true ]]; then
        cfip_probe_candidates_batched "$input" "$output" "$domains" "$timeout" "$required" "$batch_size" "$max_count" || return $?
        cfip_adaptive_update_runtime "unqualified_or_probe_error" 0 "$expansion_count"
        [[ -n "$metrics" ]] && jq -cn --argjson expansion "$expansion_count" '{adaptiveFallback:true,reason:"unqualified_or_probe_error",expansionCount:$expansion}' | cfip_atomic_write "$metrics"
        return 0
    fi
    printf '%s\n' "$probed" | cfip_atomic_write "$output"
    cfip_adaptive_update_runtime "" "$(jq '.selectedK' "$plan")" "$expansion_count"
    [[ -n "$metrics" ]] && jq -cn --argjson selected "$(jq '.selectedK' "$plan")" --argjson probed "$selected_count" --argjson expansion "$expansion_count" '{adaptiveSelectedK:$selected,adaptiveProbed:$probed,adaptiveFallback:false,expansionCount:$expansion}' | cfip_atomic_write "$metrics"
}

cfip_adaptive_status_json() {
    local state evidence current aggregate last_audit next_due context context_policy='{}'
    state="$(cfip_adaptive_state_json)"; evidence="$(cfip_adaptive_evidence_json)"
    context="${CFIP_ADAPTIVE_CONTEXT_FINGERPRINT:-$(jq -r '.contextFingerprint // ""' <<<"$state")}"; current="$(jq -cn --arg ctx "$context" --argjson s "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson c "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" --argjson e "$evidence" '[ $e[] | select(.auditComplete==true and .auditCensored==false and .contextFingerprint==$ctx and .schedulerVersion==$s and .featureContractVersion==$c) ]')"
    aggregate="$(jq -cn --argjson e "$current" 'if ($e|length)==0 then {available:false,reason:"insufficient"} else {available:true,winnerRecall:([$e[].winnerRecall]|add/length),topNRecall:([$e[].topNRecall]|add/length),eligibleInsufficiencyRate:([$e[].eligibleInsufficiencyRate]|add/length),severeMissRate:([$e[].severeMiss]|add/length),estimatedProbeSavings:([$e[].probeSavings]|add/length),measurementWallClockSaving:null,sampleCount:($e|length)} end')"
    declare -F cfip_context_policy_json >/dev/null 2>&1 && context_policy="$(cfip_context_policy_json 2>/dev/null || printf '{}')"
    last_audit="$(jq -c 'sort_by(.at)|last // null' <<<"$current")"; next_due="$(jq -nr --argjson count "$(jq '.runCount//0' <<<"$state")" --argjson interval "${CFIP_ADAPTIVE_AUDIT_INTERVAL:-20}" 'if $interval>0 then (($interval-($count%$interval))%$interval) else null end')"
    jq -cn --argjson state "$state" --argjson evidence "$evidence" --argjson aggregate "$aggregate" --argjson last "$last_audit" --argjson next "$next_due" --argjson policy "$context_policy" --arg requested "${CFIP_ADAPTIVE_MEASUREMENT_MODE:-off}" --arg effective "$(cfip_adaptive_effective_mode)" \
      '$state+{requestedMode:$requested,effectiveMode:$effective,evidenceWindowSize:($evidence|length),evidenceFreshAt:([$evidence[]|.at]|max // null),available:true,partition:"native-adaptive-measurement",aggregate:$aggregate,contextPolicy:$policy,lastFullAudit:$last,nextAuditInRuns:$next}'
}

cfip_adaptive_write_evidence() {
    local input="$1" max_bytes="$CFIP_ADAPTIVE_EVIDENCE_MAX_BYTES" tmp next bytes count
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-evidence.XXXXXX")" || return 1
    cat "$input" >"$tmp" || { rm -f "$tmp"; return 1; }
    while :; do
        bytes="$(wc -c <"$tmp" 2>/dev/null || printf 0)"; ((bytes <= max_bytes)) && break
        count="$(jq 'length' "$tmp" 2>/dev/null || printf 0)"
        ((count > 1)) || { rm -f "$tmp"; return 1; }
        next="$(mktemp "${TMPDIR:-/tmp}/cfip-adaptive-evidence-next.XXXXXX")" || { rm -f "$tmp"; return 1; }
        jq '.[1:]' "$tmp" >"$next" || { rm -f "$tmp" "$next"; return 1; }; mv "$next" "$tmp"
    done
    cat "$tmp" | cfip_atomic_write "$CFIP_ADAPTIVE_EVIDENCE_FILE"; local rc=$?; rm -f "$tmp"; return "$rc"
}

cfip_adaptive_record_audit() {
    local record="$1" current next persisted state context min window count healthy negative now
    jq -e 'type=="object" and .fullAudit==true and .auditComplete==true and .auditCensored==false and (.winnerRecall|type)=="number" and (.topNRecall|type)=="number" and (.severeMiss|type)=="number" and (.eligibleInsufficiencyRate|type)=="number" and (.probeSavings|type)=="number"' "$record" >/dev/null 2>&1 || return 1
    current="$(cfip_adaptive_evidence_json)"; next="$(jq -n --argjson current "$current" --argjson item "$(cat "$record")" --argjson limit "$CFIP_ADAPTIVE_EVIDENCE_LIMIT" '$current+[$item]|.[-$limit:]')"
    printf '%s\n' "$next" >"${record}.next"; cfip_adaptive_write_evidence "${record}.next" || { rm -f "${record}.next"; return 1; }; rm -f "${record}.next"
    persisted="$(cfip_adaptive_evidence_json)"
    context="$(jq -r '.contextFingerprint // empty' "$record")"; min="${CFIP_ADAPTIVE_MIN_EVIDENCE:-50}"; window="${CFIP_ADAPTIVE_EVIDENCE_WINDOW:-100}"; now="${CFIP_ADAPTIVE_NOW:-$(date +%s)}"; state="$(cfip_adaptive_state_json)"
    count="$(jq --argjson e "$persisted" --arg ctx "$context" --argjson s "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson c "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" --argjson w "$window" '[ $e[]|select(.auditComplete==true and .auditCensored==false and .contextFingerprint==$ctx and .schedulerVersion==$s and .featureContractVersion==$c) ][-$w:]|length' <<<"$persisted")"
    healthy="$(jq --argjson e "$persisted" --arg ctx "$context" --argjson s "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson c "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" --argjson min "$min" --argjson w "$window" '[ $e[]|select(.auditComplete==true and .auditCensored==false and .contextFingerprint==$ctx and .schedulerVersion==$s and .featureContractVersion==$c) ][-$w:] as $v|if ($v|length)<$min then false else (([$v[].winnerRecall]|add/length)>=0.98 and ([$v[].topNRecall]|add/length)>=0.95 and ([$v[].severeMiss]|add/length)<=0.01 and ([$v[].eligibleInsufficiencyRate]|add/length)<=0.01 and ([$v[].probeSavings]|add/length)>=0.20) end' <<<"$persisted")"
    negative="$(jq --argjson e "$persisted" --arg ctx "$context" --argjson s "$CFIP_ADAPTIVE_SCHEDULER_VERSION" --argjson c "$CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION" --argjson w "$window" '[ $e[]|select(.auditComplete==true and .auditCensored==false and .contextFingerprint==$ctx and .schedulerVersion==$s and .featureContractVersion==$c) ][-$w:]|if length==0 then false else ((map(.severeMiss)|add/length)>0.05 or (map(.winnerRecall)|add/length)<0.90) end' <<<"$persisted")"
    if [[ "$healthy" == true ]]; then state="$(jq --argjson count "$count" --arg ctx "$context" --argjson now "$now" '.+{qualificationState:"qualified",qualificationReason:"thresholds_met",evidenceCount:$count,freshAt:$now,contextFingerprint:$ctx}' <<<"$state")"; elif [[ "$negative" == true ]]; then state="$(jq --argjson count "$count" --argjson now "$now" '.+{qualificationState:"insufficient",qualificationReason:"negative_evidence",evidenceCount:$count,freshAt:$now}' <<<"$state")"; else state="$(jq --argjson count "$count" --argjson now "$now" '.+{qualificationState:"insufficient",qualificationReason:"insufficient_evidence",evidenceCount:$count,freshAt:$now}' <<<"$state")"; fi
    state="$(jq --argjson now "$now" '.+{auditSequence:(.auditSequence+1),lastAuditAt:$now,updatedAt:$now}' <<<"$state")"; printf '%s\n' "$state" | cfip_atomic_write "$CFIP_ADAPTIVE_STATE_FILE"
}
