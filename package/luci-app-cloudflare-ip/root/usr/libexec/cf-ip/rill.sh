#!/usr/bin/env bash
# shellcheck shell=bash

# Cloudflare owns this mapping layer. The generic Runtime remains an external,
# product-neutral dependency and never receives shell, UCI or service access.
CFIP_RILL_SCHEMA_FILE="${CFIP_RILL_SCHEMA_FILE:-/usr/share/cf-ip/rill-feature-schema-v2.json}"
CFIP_RILL_SCHEMA_VERSION=2
CFIP_RILL_MODEL_GENERATION=2
CFIP_RILL_PARTITION_KEY="${CFIP_RILL_PARTITION_KEY:-default}"
CFIP_RILL_BASE_DIR="${CFIP_STATUS_DIR:-}"
if [[ -z "$CFIP_RILL_BASE_DIR" ]]; then
    CFIP_RILL_BASE_DIR="${CFIP_RILL_STATE:-/etc/cf_ip}"
    [[ "$CFIP_RILL_BASE_DIR" == */* ]] && CFIP_RILL_BASE_DIR="${CFIP_RILL_BASE_DIR%/*}" || CFIP_RILL_BASE_DIR="/etc/cf_ip"
fi
CFIP_RILL_HISTORY_FILE="${CFIP_RILL_HISTORY_FILE:-$CFIP_RILL_BASE_DIR/candidate-history.json}"
CFIP_RILL_PENDING_FILE="${CFIP_RILL_PENDING_FILE:-$CFIP_RILL_BASE_DIR/rill-pending-feedback.json}"
CFIP_RILL_QUALIFICATION_FILE="${CFIP_RILL_QUALIFICATION_FILE:-$CFIP_RILL_BASE_DIR/rill-qualification.json}"
CFIP_RILL_STATE_META_FILE="${CFIP_RILL_STATE_META_FILE:-$CFIP_RILL_BASE_DIR/rill-state-meta.json}"

cfip_rill_schema_hash() {
    [[ -s "$CFIP_RILL_SCHEMA_FILE" ]] || return 1
    sha256sum "$CFIP_RILL_SCHEMA_FILE" | awk '{print $1}'
}

cfip_rill_state_generation() {
    [[ -f "$CFIP_RILL_STATE" ]] || { printf '0'; return 0; }
    jq -r --arg name "cloudflare-ip" --arg partition "$CFIP_RILL_PARTITION_KEY" \
      '([.partitions[]? | select(.clientIdentityName==$name and .partitionKey==$partition)][0].handlerSnapshot.stateGeneration // 0)' \
      "$CFIP_RILL_STATE" 2>/dev/null || printf '0'
}

cfip_rill_prepare_state() {
    [[ -z "${CFIP_RILL_STATE:-}" ]] && return 0
    mkdir -p "${CFIP_RILL_STATE%/*}"
    [[ ! -e "$CFIP_RILL_STATE" ]] && return 0
    local reason="" valid=true state_width
    jq -e '.formatVersion == 1 and (.partitions|type == "array") and ((.partitions|length) > 0)' \
      "$CFIP_RILL_STATE" >/dev/null 2>&1 || valid=false
    if [[ "$valid" == true ]]; then
        state_width="$(jq -r --arg name cloudflare-ip --arg partition "$CFIP_RILL_PARTITION_KEY" \
          '([.partitions[]? | select(.clientIdentityName==$name and .partitionKey==$partition)][0].handlerSnapshot.state|implode|fromjson|.featureCount // 0)' \
          "$CFIP_RILL_STATE" 2>/dev/null || printf 0)"
        [[ "$state_width" == 0 || "$state_width" == 22 ]] || { valid=false; reason="feature_schema_v2_required"; }
    else
        reason="invalid_or_legacy_snapshot"
    fi
    [[ "$valid" == true ]] && return 0
    [[ -n "$reason" ]] || reason="state_validation_failed"
    local stamp quarantine
    stamp="$(date +%Y%m%d%H%M%S)"
    quarantine="${CFIP_RILL_STATE}.quarantine.${stamp}"
    [[ -e "$quarantine" ]] && quarantine="${quarantine}.$$"
    mv "$CFIP_RILL_STATE" "$quarantine" || return 1
    jq -cn --arg reason "$reason" --arg from "$quarantine" --argjson schema "$CFIP_RILL_SCHEMA_VERSION" \
      '{resetRequired:true,resetReason:$reason,migratedFrom:$from,quarantinedState:true,featureSchemaVersion:$schema,at:(now|floor)}' \
      | cfip_atomic_write "$CFIP_RILL_STATE_META_FILE"
    cfip_log "Rill state quarantined: $reason ($quarantine)"
}

cfip_rill_history_json() {
    [[ -s "$CFIP_RILL_HISTORY_FILE" ]] && jq -e 'type == "object"' "$CFIP_RILL_HISTORY_FILE" >/dev/null 2>&1 && cat "$CFIP_RILL_HISTORY_FILE" || printf '{}'
}

cfip_rill_update_history() {
    local observations="$1" now tmp
    [[ -s "$observations" ]] || return 0
    now="$(date +%s)"
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-history.XXXXXX")" || return 1
    cfip_rill_history_json | jq --argjson now "$now" --slurpfile rows "$observations" '
      def row: {successCount:0,failureCount:0,latencySamples:[],lastSeen:0,lastSuccess:0,consecutiveFailures:0,lastSelected:false};
      reduce ($rows[0][]? // {}) as $c (.;
        ($c.ip|tostring) as $id |
        (.[$id] // row) as $old |
        (($c.eligible == true) and (($c.probeSummary.totalMs // null)|type == "number")) as $ok |
        (($old.latencySamples + [($c.probeSummary.totalMs // null)|select(type=="number")])[-32:]) as $samples |
        .[$id] = ($old + {
          successCount: (($old.successCount // 0) + (if $ok then 1 else 0 end)),
          failureCount: (($old.failureCount // 0) + (if $ok then 0 else 1 end)),
          latencySamples: $samples,
          lastSeen: $now,
          lastSuccess: (if $ok then $now else ($old.lastSuccess // 0) end),
          consecutiveFailures: (if $ok then 0 else (($old.consecutiveFailures // 0)+1) end)
        })
      ) | to_entries | sort_by(.value.lastSeen) | .[-256:] | from_entries
    ' >"$tmp" && cat "$tmp" | cfip_atomic_write "$CFIP_RILL_HISTORY_FILE"
    local rc=$?; rm -f "$tmp"; return "$rc"
}

cfip_rill_probe_priority() {
    local input="$1" output="$2" history
    [[ -s "$input" ]] || { printf '[]\n' | cfip_atomic_write "$output"; return 0; }
    if [[ "${CFIP_RILL_ENABLED:-false}" != true || "${CFIP_RILL_MODE:-off}" == off ]]; then
        cat "$input" | cfip_atomic_write "$output"
        return $?
    fi
    history="$(cfip_rill_history_json)"
    jq --argjson history "$history" '
      sort_by(
        (.ip|tostring) as $id |
        (-((($history[$id].successCount//0) / (($history[$id].successCount//0)+($history[$id].failureCount//0)+1)))),
        ($history[$id].consecutiveFailures//0),
        (.cfstRank//999999),
        (.ip|tostring)
      )
    ' "$input" | cfip_atomic_write "$output"
}

cfip_rill_mark_selected() {
    local id="$1" current
    [[ -n "$id" ]] || return 0
    current="$(cfip_rill_history_json)"
    printf '%s\n' "$current" | jq --arg id "$id" 'with_entries(.value.lastSelected = (.key == $id))' | cfip_atomic_write "$CFIP_RILL_HISTORY_FILE"
}

cfip_rill_qualification_json() {
    if [[ -s "$CFIP_RILL_QUALIFICATION_FILE" ]] && jq -e 'type == "object"' "$CFIP_RILL_QUALIFICATION_FILE" >/dev/null 2>&1; then
        cat "$CFIP_RILL_QUALIFICATION_FILE"
    else
        jq -cn --argjson minimum "${CFIP_RILL_MIN_FEEDBACK_SAMPLES:-30}" \
          '{state:"cold",validFeedback:0,attributedFeedback:0,delayedCompleted:0,disagreements:0,errors:0,candidateFailures:0,recentRewards:[],lastReward:null,rollingReward:null,minFeedbackSamples:$minimum,updatedAt:null}'
    fi
}

cfip_rill_qualified() {
    local state
    state="$(cfip_rill_qualification_json | jq -r '.state // "cold"')"
    [[ "$state" == shadow-qualified || "$state" == guarded-assisted ]]
}

cfip_rill_record_qualification() {
    local candidate_outcome="$1" attribution="$2" delayed="$3" error="$4" reward="${5:-}" current state count attributed completed errors failures minimum recent_rewards
    current="$(cfip_rill_qualification_json)"
    state="$(jq -r '.state // "cold"' <<<"$current")"
    count="$(jq -r '.validFeedback // 0' <<<"$current")"; attributed="$(jq -r '.attributedFeedback // 0' <<<"$current")"
    completed="$(jq -r '.delayedCompleted // 0' <<<"$current")"; errors="$(jq -r '.errors // 0' <<<"$current")"; failures="$(jq -r '.candidateFailures // 0' <<<"$current")"
    recent_rewards="$(jq -c '.recentRewards // []' <<<"$current")"
    minimum="${CFIP_RILL_MIN_FEEDBACK_SAMPLES:-30}"
    [[ "$candidate_outcome" == success || "$candidate_outcome" == failure ]] && count=$((count+1))
    [[ "$candidate_outcome" == failure ]] && failures=$((failures+1))
    [[ "$attribution" == true ]] && attributed=$((attributed+1))
    [[ "$delayed" == true ]] && completed=$((completed+1))
    [[ "$error" == true ]] && errors=$((errors+1))
    if [[ "$reward" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        recent_rewards="$(jq -cn --argjson a "$recent_rewards" --argjson reward "$reward" '($a+[$reward])[-32:]')"
    fi
    [[ "$state" == reset-required ]] || {
        if ((count >= minimum && attributed == count && errors == 0 && completed * 100 >= count * 80)); then state=shadow-qualified
        elif ((errors >= 3)); then state=degraded
        elif ((count > 0)); then state=learning
        else state=cold; fi
    }
    jq -cn --arg state "$state" --argjson count "$count" --argjson attributed "$attributed" \
      --argjson completed "$completed" --argjson errors "$errors" --argjson failures "$failures" --argjson rewards "$recent_rewards" --argjson minimum "$minimum" \
      '{state:$state,validFeedback:$count,attributedFeedback:$attributed,delayedCompleted:$completed,errors:$errors,candidateFailures:$failures,recentRewards:$rewards,lastReward:($rewards[-1] // null),rollingReward:(if ($rewards|length)>0 then ($rewards|add/length) else null end),minFeedbackSamples:$minimum,updatedAt:(now|floor)}' \
      | cfip_atomic_write "$CFIP_RILL_QUALIFICATION_FILE"
}

cfip_rill_pending_count() {
    [[ -s "$CFIP_RILL_PENDING_FILE" ]] && jq 'length' "$CFIP_RILL_PENDING_FILE" 2>/dev/null || printf 0
}

cfip_rill_runtime_call() {
    local request="$1" response schema request_file response_file rc=0 response_bytes
    [[ -x "$CFIP_RILL_RUNTIME" ]] || return 3
    schema="$(cfip_rill_schema_hash)" || return 4
    cfip_rill_prepare_state || return 10
    mkdir -p "${CFIP_RILL_STATE%/*}"
    request_file="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-call.XXXXXX")" || return 4
    response_file="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-response.XXXXXX")" || { rm -f "$request_file"; return 4; }
    printf '%s\n' "$request" >"$request_file"
    cfip_run_with_timeout "${CFIP_RILL_TIMEOUT_S:-2}" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation "$5"' \
      sh "$request_file" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$schema" "$CFIP_RILL_MODEL_GENERATION" >"$response_file" 2>>"$CFIP_LOG_FILE" || rc=$?
    response_bytes="$(wc -c <"$response_file" 2>/dev/null || printf 0)"
    if ((rc != 0)); then rm -f "$request_file" "$response_file"; return "$rc"; fi
    if ((response_bytes > 262144)); then rm -f "$request_file" "$response_file"; return 8; fi
    response="$(cat "$response_file")"; rm -f "$request_file" "$response_file"
    [[ -n "$response" ]] || return 6
    printf '%s' "$response"
}

cfip_rill_status_json() {
    local request response schema qualification meta history pending
    if [[ "${CFIP_RILL_ENABLED:-false}" != true || "${CFIP_RILL_MODE:-off}" == off ]]; then
        jq -cn '{available:false,state:"disabled",mode:"off",channel:"preview",featureSchemaVersion:2,modelGeneration:2}'
        return 0
    fi
    schema="$(cfip_rill_schema_hash 2>/dev/null || true)"
    [[ -n "$schema" ]] || { jq -cn --arg mode "$CFIP_RILL_MODE" '{available:false,state:"schema-unavailable",mode:$mode}'; return 0; }
    request="$(jq -cn --arg id "status-${CFIP_RUN_ID:-status}" --arg schema "$schema" --arg partition "$CFIP_RILL_PARTITION_KEY" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},partitionKey:$partition,featureSchemaHash:$schema,modelGeneration:2,stateGeneration:0,payloadLimit:1048576,request:{method:"handshake"}}')"
    response="$(cfip_rill_runtime_call "$request" 2>/dev/null || true)"
    qualification="$(cfip_rill_qualification_json)"; meta='{}'; [[ -s "$CFIP_RILL_STATE_META_FILE" ]] && meta="$(cat "$CFIP_RILL_STATE_META_FILE")"
    history="$(cfip_rill_history_json)"; pending="$(cfip_rill_pending_count)"
    if jq -e --arg id "status-${CFIP_RUN_ID:-status}" --arg schema "$schema" \
      '.requestId==$id and .response.kind=="handshake" and .apiVersion==3 and (.response.capabilities|type=="array") and .response.featureSchemaHash==$schema and (.response.capabilities|index("org.rill.preview.decide")) and (.response.capabilities|index("org.rill.preview.feedback")) and .response.handlerApiVersion==2' <<<"$response" >/dev/null 2>&1; then
        jq -cn --arg mode "$CFIP_RILL_MODE" --arg schema "$schema" --argjson s "$response" --argjson q "$qualification" --argjson m "$meta" --argjson h "$history" --argjson pending "$pending" \
          '{available:true,state:"healthy",channel:($s.response.channel//"preview"),mode:$mode,runtimeVersion:$s.runtimeIdentity.version,runtimeApiVersion:$s.apiVersion,capabilities:$s.response.capabilities,featureSchemaVersion:2,featureSchemaHash:$schema,modelGeneration:2,stateGeneration:$s.stateGeneration,handlerApiVersion:$s.response.handlerApiVersion,qualificationState:(if $m.resetRequired==true then "reset-required" else ($q.state//"cold") end),validFeedback:($q.validFeedback//0),attributedFeedback:($q.attributedFeedback//0),delayedCompleted:($q.delayedCompleted//0),candidateFailures:($q.candidateFailures//0),lastReward:($q.lastReward//null),rollingReward:($q.rollingReward//null),pendingDelayedFeedback:$pending,candidateHistoryCount:($h|length),lastResetReason:($m.resetReason//null),resetRequired:($m.resetRequired//false),resourcePressure:false}'
    else
        jq -cn --arg mode "$CFIP_RILL_MODE" --argjson q "$qualification" --argjson m "$meta" --argjson pending "$pending" \
          '{available:false,state:"incompatible",channel:"preview",mode:$mode,runtimeApiVersion:3,featureSchemaVersion:2,modelGeneration:2,qualificationState:(if $m.resetRequired==true then "reset-required" else $q.state end),pendingDelayedFeedback:$pending,lastResetReason:($m.resetReason//null),resetRequired:($m.resetRequired//false)}'
    fi
}

cfip_rill_actions_json() {
    local history now
    history="$(cfip_rill_history_json)"; now="$(date +%s)"
    jq -c --argjson history "$history" --argjson now "$now" '
      def n($v;$fallback): if ($v|type)=="number" and ($v|isfinite) then $v else $fallback end;
      def clamp($v;$fallback;$lo;$hi): (n($v;$fallback) | if . < $lo then $lo elif . > $hi then $hi else . end);
      def ms($v): clamp($v;10000;0;10000)/10000;
      def samples($v): (($v|map(select(type=="number"))|sort) // []);
      [.[] as $candidate |
        ($history[($candidate.ip|tostring)] // {}) as $h |
        (samples($h.latencySamples // [])) as $lat |
        ($lat|length) as $len |
        (if $len>0 then $lat[($len-1)/2|floor] else 10000 end) as $median |
        (if $len>0 then $lat[([$len*0.95|floor, $len-1]|min)] else 10000 end) as $p95 |
        {id:($candidate.ip|tostring),features:[
          ms($candidate.avgLatencyMs), clamp($candidate.downloadMBps;0;0;10000)/100,
          clamp($candidate.lossRate;1;0;1), ms($candidate.probeSummary.connectMs), ms($candidate.probeSummary.tlsMs),
          ms($candidate.probeSummary.ttfbMs), ms($candidate.probeSummary.totalMs), clamp($candidate.cfstRank;128;1;128)/128,
          (if $candidate.family=="ipv6" then 1 else 0 end), clamp($candidate.sourceCount;0;0;16)/16,
          (if $candidate.sourceStale==true then 1 else 0 end),
          (if any($candidate.sources[]?; tostring|test("official";"i")) then 1 else 0 end),
          (if any($candidate.sources[]?; tostring|test("community";"i")) then 1 else 0 end),
          (if any($candidate.sources[]?; tostring|test("manual";"i")) then 1 else 0 end),
          (if (($h.successCount//0)+($h.failureCount//0)) > 0 then clamp((($h.successCount//0) / (($h.successCount//0)+($h.failureCount//0)));0.5;0;1) else 0.5 end),
          (if (($h.successCount//0)+($h.failureCount//0)) > 0 then clamp((($h.failureCount//0) / (($h.successCount//0)+($h.failureCount//0)));0.5;0;1) else 0.5 end),
          clamp($median;10000;0;10000)/10000, clamp($p95;10000;0;10000)/10000,
          clamp($h.consecutiveFailures;0;0;10)/10, clamp((($now-($h.lastSeen//$now))/86400);1;0;1),
          (if $h.lastSelected==true then 1 else 0 end), 0.5
        ]}]
    ' "$1"
}

cfip_rill_rank_shadow() {
    local native_json="$1" output="$2" request tmp rc=0 response_bytes native_set rill_set schema actions selected_id generation scores
    [[ "${CFIP_RILL_ENABLED:-false}" == true && "${CFIP_RILL_MODE:-off}" != off ]] || return 2
    [[ -x "$CFIP_RILL_RUNTIME" ]] || return 3
    schema="$(cfip_rill_schema_hash)" || return 4; actions="$(cfip_rill_actions_json "$native_json")" || return 4
    request="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-request.XXXXXX")" || return 4
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-response.XXXXXX")" || { rm -f "$request"; return 4; }
    jq -cn --arg id "decision-$CFIP_RUN_ID" --arg schema "$schema" --arg partition "$CFIP_RILL_PARTITION_KEY" --argjson generation "$(cfip_rill_state_generation)" --argjson actions "$actions" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},partitionKey:$partition,capability:"org.rill.preview.decide",featureSchemaHash:$schema,modelGeneration:2,stateGeneration:$generation,payloadLimit:1048576,request:{method:"decide",context:{actions:$actions}}}' >"$request"
    cfip_run_with_timeout "${CFIP_RILL_TIMEOUT_S:-2}" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation "$5"' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$schema" "$CFIP_RILL_MODEL_GENERATION" >"$tmp" 2>>"$CFIP_LOG_FILE" || rc=$?
    rm -f "$request"; response_bytes="$(wc -c <"$tmp" 2>/dev/null || printf 0)"
    if ((rc != 0 || response_bytes > 262144)) || ! jq -e --arg id "decision-$CFIP_RUN_ID" '.requestId==$id and .response.kind=="result" and .response.output.accepted==true and (.response.output.selectedActionId|type=="string") and ((.response.output.selectedActionId|length)>0) and (.response.output.scores|type=="array") and ((.response.output.scores|length)>0) and all(.response.output.scores[]; (.id|type)=="string" and (.score|type=="number"))' "$tmp" >/dev/null 2>&1; then rm -f "$tmp"; return 5; fi
    selected_id="$(jq -r '.response.output.selectedActionId' "$tmp")"; native_set="$(jq -c '[.[].ip|tostring]|sort' "$native_json")"; rill_set="$(jq -c '[.response.output.scores[].id]|sort' "$tmp")"
    [[ "$native_set" == "$rill_set" ]] || { rm -f "$tmp"; return 6; }
    jq -e --arg id "$selected_id" 'any(.[]; (.ip|tostring)==$id)' "$native_json" >/dev/null || { rm -f "$tmp"; return 7; }
    generation="$(jq -r '.stateGeneration' "$tmp")"; scores="$(jq -c '[.response.output.scores[]] | sort_by(-.score,.id)' "$tmp")"
    jq --arg selected "$selected_id" --arg generation "$generation" --argjson candidates "$(cat "$native_json")" --argjson scores "$scores" \
      '{success:true,decisionId:.requestId,selectedActionId:$selected,generation:($generation|tonumber),candidates:($candidates|map(. as $c | ($scores|to_entries|map(select(.value.id==($c.ip|tostring)))[0]) as $s | $c + {rillScore:($s.value.score//null),rillRank:(if $s then ($s.key+1) else null end),scoreMargin:(if $s and $scores[($s.key+1)] then ($s.value.score-$scores[$s.key+1].score) else null end)}) | sort_by(.rillRank // 99999)),runtimeApiVersion:.apiVersion,shadowCandidateInvariant:true}' "$tmp" >"$output"
    rm -f "$tmp"
}

cfip_rill_shadow_observe() {
    local decision="$1" rill="$2" domains="$3" timeout_s="$4" output="$5" selected candidate probe all_ok=true probes='[]' domain family
    selected="$(jq -r '.selectedActionId // empty' "$decision")"; [[ -n "$selected" ]] || return 2
    candidate="$(jq -c --arg id "$selected" '.candidates[]|select((.ip|tostring)==$id)' "$rill" | head -n1)"; [[ -n "$candidate" ]] || return 2
    family="$(jq -r '.family' <<<"$candidate")"; IFS=',' read -r -a domain_list <<<"$domains"
    for domain in "${domain_list[@]}"; do
        probe="$(cfip_probe_one "$selected" "$domain" "$family" "$timeout_s")"; probes="$(jq -cn --argjson a "$probes" --argjson p "$probe" '$a+[$p]')"; [[ "$(jq -r '.success' <<<"$probe")" == true ]] || all_ok=false
    done
    jq -cn --arg runId "${CFIP_RUN_ID:-}" --arg ip "$selected" --arg decisionId "$(jq -r '.decisionId' "$decision")" --argjson ok "$all_ok" --argjson probes "$probes" \
      '($probes|map(select(.success==true))) as $s | {schemaVersion:2,runId:$runId,decisionId:$decisionId,validated:$ok,candidateOutcome:(if $ok then "success" else "failure" end),hostOutcome:"success",censored:false,observedIp:$ip,decisionActionId:$ip,probes:$probes,reward:(if $ok then ((1/(1+((($s|map(.totalMs)|add/length)//10000)/1000))) | if . < -1 then -1 elif . > 1 then 1 else . end) else -1 end)}' | cfip_atomic_write "$output"
}

cfip_rill_feedback() {
    local decision_json="$1" outcome_json="$2" request response_file rc=0 decision_id selected_id observed_id schema state_generation expected_request_id reward candidate_outcome host_outcome delayed
    [[ "${CFIP_RILL_ENABLED:-false}" == true && -x "$CFIP_RILL_RUNTIME" ]] || return 0
    candidate_outcome="$(jq -r '.candidateOutcome // (if .validated==true then "success" else "unknown" end)' "$outcome_json")"; host_outcome="$(jq -r '.hostOutcome // "success"' "$outcome_json")"
    [[ "$host_outcome" == success && "$candidate_outcome" != unknown && "$(jq -r '.censored // false' "$outcome_json")" != true ]] || return 0
    decision_id="$(jq -r '.decisionId // empty' "$decision_json")"; selected_id="$(jq -r '.selectedActionId // empty' "$decision_json")"; observed_id="$(jq -r '.observedIp // .decisionActionId // empty' "$outcome_json")"
    [[ -n "$decision_id" && -n "$selected_id" && "$observed_id" == "$selected_id" ]] || { cfip_log "Rill feedback censored: observed action does not match decision"; cfip_rill_record_qualification "$candidate_outcome" false false true; return 12; }
    schema="$(cfip_rill_schema_hash)" || return 1; state_generation="$(cfip_rill_state_generation)"; expected_request_id="feedback-${CFIP_RUN_ID:-feedback}"
    reward="$(jq -r '.reward // (if .candidateOutcome=="failure" then -1 else 0 end)' "$outcome_json")"
    request="$(jq -cn --arg id "$expected_request_id" --arg decisionId "$decision_id" --arg selected "$selected_id" --arg schema "$schema" --arg partition "$CFIP_RILL_PARTITION_KEY" --argjson stateGeneration "$state_generation" --argjson reward "$reward" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},partitionKey:$partition,capability:"org.rill.preview.feedback",featureSchemaHash:$schema,modelGeneration:2,stateGeneration:$stateGeneration,payloadLimit:1048576,request:{method:"feedback",decisionId:$decisionId,selectedActionId:$selected,reward:$reward,outcomeTimeMs:(now*1000|floor),generation:2}}')"
    response_file="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-feedback-response.XXXXXX")" || return 1
    cfip_run_with_timeout "${CFIP_RILL_TIMEOUT_S:-2}" sh -c 'printf "%s\n" "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation "$5"' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$schema" "$CFIP_RILL_MODEL_GENERATION" >"$response_file" 2>>"$CFIP_LOG_FILE" || rc=$?
    if ((rc != 0)) || ! jq -e --arg id "$expected_request_id" '(.requestId|type)=="string" and .requestId==$id and .apiVersion==3 and ((.response.kind=="result" and .response.output.accepted==true) or (.response.kind=="error" and (.response.error.code|type)=="string"))' "$response_file" >/dev/null 2>&1; then local failure_rc=8; ((rc != 0)) && failure_rc="$rc"; cfip_log "Rill feedback response invalid"; rm -f "$response_file"; cfip_rill_record_qualification "$candidate_outcome" false false true; return "$failure_rc"; fi
    if jq -e '.response.kind=="error"' "$response_file" >/dev/null 2>&1; then cfip_log "Rill feedback rejected: code=$(jq -r '.response.error.code' "$response_file")"; rm -f "$response_file"; cfip_rill_record_qualification "$candidate_outcome" false false true; return 9; fi
    rm -f "$response_file"; cfip_rill_mark_selected "$selected_id"; delayed="${CFIP_RILL_PROCESSING_DELAYED:-false}"; cfip_rill_record_qualification "$candidate_outcome" true "$delayed" false "$reward"; return 0
}

cfip_rill_queue_feedback() {
    local decision="$1" outcome="$2" due="$(($(date +%s)+${CFIP_RILL_DELAYED_FEEDBACK_SECONDS:-600}))" current
    current='[]'; [[ -s "$CFIP_RILL_PENDING_FILE" ]] && current="$(jq -e 'type=="array"' "$CFIP_RILL_PENDING_FILE" 2>/dev/null && cat "$CFIP_RILL_PENDING_FILE" || printf '[]')"
    jq -cn --argjson current "$current" --argjson due "$due" --argjson decision "$(cat "$decision")" --argjson outcome "$(cat "$outcome")" \
      '($current + [{dueAt:$due,decision:$decision,outcome:$outcome}])[-64:]' | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"
}

cfip_rill_process_pending_feedback() {
    [[ -s "$CFIP_RILL_PENDING_FILE" ]] || return 0
    local now current due item tmp_decision tmp_outcome feedback_rc remaining='[]'
    now="$(date +%s)"
    current="$(cat "$CFIP_RILL_PENDING_FILE" 2>/dev/null || printf '[]')"
    while IFS= read -r item; do
        due="$(jq -r '.dueAt // 0' <<<"$item")"
        if ((due > now)); then remaining="$(jq -cn --argjson a "$remaining" --argjson i "$item" '$a+[$i]')"; continue; fi
        tmp_decision="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-pending-decision.XXXXXX")"; tmp_outcome="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-pending-outcome.XXXXXX")"
        jq -c '.decision' <<<"$item" >"$tmp_decision"; jq -c '.outcome' <<<"$item" >"$tmp_outcome"
        feedback_rc=0
        CFIP_RILL_PROCESSING_DELAYED=true
        cfip_rill_feedback "$tmp_decision" "$tmp_outcome" || feedback_rc=$?
        CFIP_RILL_PROCESSING_DELAYED=false
        if ((feedback_rc != 0 && feedback_rc != 9)); then remaining="$(jq -cn --argjson a "$remaining" --argjson i "$item" '$a+[$i]')"; fi
        rm -f "$tmp_decision" "$tmp_outcome"
    done < <(jq -c '.[]?' <<<"$current")
    printf '%s\n' "$remaining" | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"
}

cfip_rill_inspect_json() {
    local schema request response
    schema="$(cfip_rill_schema_hash 2>/dev/null || true)"; [[ -n "$schema" ]] || return 1
    request="$(jq -cn --arg id "inspect-${CFIP_RUN_ID:-status}" --arg schema "$schema" --arg partition "$CFIP_RILL_PARTITION_KEY" --argjson generation "$(cfip_rill_state_generation)" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},partitionKey:$partition,capability:"org.rill.preview.inspect",featureSchemaHash:$schema,modelGeneration:2,stateGeneration:$generation,payloadLimit:1048576,request:{method:"inspect"}}')"
    response="$(cfip_rill_runtime_call "$request" 2>/dev/null || true)"; jq -c '.response.summary // {}' <<<"$response" 2>/dev/null || printf '{}'
}
