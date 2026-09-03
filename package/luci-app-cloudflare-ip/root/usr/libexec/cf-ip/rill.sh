#!/usr/bin/env bash
# shellcheck shell=bash

# Cloudflare owns this mapping layer. The generic Runtime remains an external,
# product-neutral dependency and never receives shell, UCI or service access.
CFIP_RILL_SCHEMA_FILE="${CFIP_RILL_SCHEMA_FILE:-/usr/share/cf-ip/rill-feature-schema-v2.json}"
CFIP_RILL_SCHEMA_VERSION=2
CFIP_RILL_MODEL_GENERATION=2
CFIP_RILL_CANDIDATE_PARTITION_KEY="${CFIP_RILL_CANDIDATE_PARTITION_KEY:-candidate}"
CFIP_RILL_PARTITION_KEY="$CFIP_RILL_CANDIDATE_PARTITION_KEY"
CFIP_RILL_BASE_DIR="${CFIP_STATUS_DIR:-}"
if [[ -z "$CFIP_RILL_BASE_DIR" ]]; then
    CFIP_RILL_BASE_DIR="${CFIP_RILL_STATE:-/etc/cf_ip}"
    [[ "$CFIP_RILL_BASE_DIR" == */* ]] && CFIP_RILL_BASE_DIR="${CFIP_RILL_BASE_DIR%/*}" || CFIP_RILL_BASE_DIR="/etc/cf_ip"
fi
CFIP_RILL_HISTORY_FILE="${CFIP_RILL_HISTORY_FILE:-$CFIP_RILL_BASE_DIR/candidate-history.json}"
CFIP_RILL_PENDING_FILE="${CFIP_RILL_PENDING_FILE:-$CFIP_RILL_BASE_DIR/rill-pending-feedback.json}"
CFIP_RILL_QUALIFICATION_FILE="${CFIP_RILL_QUALIFICATION_FILE:-$CFIP_RILL_BASE_DIR/rill-qualification.json}"
CFIP_RILL_STATE_META_FILE="${CFIP_RILL_STATE_META_FILE:-$CFIP_RILL_BASE_DIR/rill-state-meta.json}"
CFIP_RILL_PREFIX_HISTORY_FILE="${CFIP_RILL_PREFIX_HISTORY_FILE:-$CFIP_RILL_BASE_DIR/prefix-history.json}"
CFIP_RILL_COLO_HISTORY_FILE="${CFIP_RILL_COLO_HISTORY_FILE:-$CFIP_RILL_BASE_DIR/colo-history.json}"
CFIP_RILL_DELAYED_FEEDBACK_EXPIRY_SECONDS="${CFIP_RILL_DELAYED_FEEDBACK_EXPIRY_SECONDS:-86400}"
CFIP_RILL_CONTEXT_SCHEMA_VERSION=1
CFIP_RILL_EVIDENCE_FILE="${CFIP_RILL_EVIDENCE_FILE:-$CFIP_RILL_BASE_DIR/rill-evidence.json}"
CFIP_RILL_EVIDENCE_LIMIT="${CFIP_RILL_EVIDENCE_LIMIT:-64}"
CFIP_RILL_EVIDENCE_MAX_BYTES="${CFIP_RILL_EVIDENCE_MAX_BYTES:-262144}"
CFIP_RILL_HOLDOUT_INTERVAL="${CFIP_RILL_HOLDOUT_INTERVAL:-5}"
CFIP_RILL_HOLDOUT_STATE_FILE="${CFIP_RILL_HOLDOUT_STATE_FILE:-$CFIP_RILL_BASE_DIR/rill-holdout-cadence.json}"
CFIP_RILL_REWARD_TIE_EPSILON="${CFIP_RILL_REWARD_TIE_EPSILON:-0.02}"
CFIP_RILL_EVALUATION_MAX_AGE_SECONDS="${CFIP_RILL_EVALUATION_MAX_AGE_SECONDS:-86400}"

cfip_rill_now_seconds() {
    if [[ "${CFIP_RILL_FAKE_NOW:-}" =~ ^[0-9]+$ ]]; then
        printf '%s' "$CFIP_RILL_FAKE_NOW"
    else
        date +%s
    fi
}

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

cfip_rill_lineage_id() {
    local meta='{}' lineage
    [[ -s "$CFIP_RILL_STATE_META_FILE" ]] && meta="$(jq -c 'if type=="object" then . else {} end' "$CFIP_RILL_STATE_META_FILE" 2>/dev/null || printf '{}')"
    lineage="$(jq -r '.lineageId // empty' <<<"$meta")"
    if [[ "$lineage" =~ ^[0-9a-f]{64}$ ]]; then
        printf '%s' "$lineage"
        return 0
    fi
    lineage="$(printf '%s:%s:%s' "${CFIP_RILL_STATE:-}" "$(date +%s%N 2>/dev/null || date +%s)" "${RANDOM:-0}" | sha256sum | awk '{print $1}')"
    jq --arg lineage "$lineage" '. + {lineageId:$lineage}' <<<"$meta" | cfip_atomic_write "$CFIP_RILL_STATE_META_FILE" || return 1
    printf '%s' "$lineage"
}

cfip_rill_reset_holdout_cadence() {
    local fingerprint="${1:-}" lineage="${2:-}"
    [[ -n "$fingerprint" ]] || fingerprint="$(cfip_rill_context_fingerprint 2>/dev/null || printf '')"
    [[ -n "$lineage" ]] || lineage="$(cfip_rill_lineage_id 2>/dev/null || printf '')"
    jq -cn --arg fp "$fingerprint" --arg lineage "$lineage" \
      '{schemaVersion:1,contextFingerprint:$fp,stateLineage:$lineage,assistedDisagreementCount:0,lastDecisionId:null,updatedAt:(now|floor)}' \
      | cfip_atomic_write "$CFIP_RILL_HOLDOUT_STATE_FILE"
}

cfip_rill_rotate_lineage() {
    local reason="${1:-reset}" lineage meta='{}'
    lineage="$(printf '%s:%s:%s' "${CFIP_RILL_STATE:-}" "$(date +%s%N 2>/dev/null || date +%s)" "${RANDOM:-0}" | sha256sum | awk '{print $1}')"
    [[ -s "$CFIP_RILL_STATE_META_FILE" ]] && meta="$(jq -c 'if type=="object" then . else {} end' "$CFIP_RILL_STATE_META_FILE" 2>/dev/null || printf '{}')"
    jq --arg reason "$reason" --arg lineage "$lineage" --argjson schema "$CFIP_RILL_SCHEMA_VERSION" \
      '. + {resetRequired:false,resetReason:$reason,lineageId:$lineage,featureSchemaVersion:$schema,at:(now|floor)}' <<<"$meta" \
      | cfip_atomic_write "$CFIP_RILL_STATE_META_FILE"
}

cfip_rill_context_json() {
    local domains="${CFIP_TARGET_DOMAINS:-}" protocol="${CFIP_SPEEDTEST_PROTOCOL:-tcp}" ip_type="${CFIP_IP_TYPE:-ipv4}" colo="${CFIP_SPEEDTEST_CFCOLO:-}"
    jq -cn --arg domains "$domains" --arg protocol "$protocol" --arg ipType "$ip_type" --arg colo "$colo" \
      '{normalizedTargetDomains:($domains|split(",")|map(gsub("^[[:space:]]+|[[:space:]]+$";"")|ascii_downcase)|map(select(length>0))|unique|sort),speedtestProtocol:($protocol|ascii_downcase),ipType:($ipType|ascii_downcase),cfColoRestriction:($colo|gsub("^[[:space:]]+|[[:space:]]+$";"")|ascii_downcase)}' | jq -cS .
}

cfip_rill_context_fingerprint() {
    local context="$(cfip_rill_context_json)"
    printf '%s' "$context" | sha256sum | awk '{print $1}'
}

cfip_rill_context_guard() {
    local context fingerprint meta stored stamp file quarantine pending at lineage
    context="$(cfip_rill_context_json)" || return 1
    fingerprint="$(printf '%s' "$context" | sha256sum | awk '{print $1}')"
    meta='{}'
    [[ -s "$CFIP_RILL_STATE_META_FILE" ]] && meta="$(jq -c 'if type=="object" then . else {} end' "$CFIP_RILL_STATE_META_FILE" 2>/dev/null || printf '{}')"
    stored="$(jq -r '.contextFingerprint // empty' <<<"$meta")"
    mkdir -p "$CFIP_RILL_BASE_DIR"
    if [[ -z "$stored" ]]; then
        jq --arg fp "$fingerprint" --argjson context "$context" --argjson schema "$CFIP_RILL_CONTEXT_SCHEMA_VERSION" \
          '. + {contextSchemaVersion:$schema,contextFingerprint:$fp,currentContextFingerprint:$fp,contextSummary:$context,contextChanged:false,contextTransitionPending:false}' <<<"$meta" | cfip_atomic_write "$CFIP_RILL_STATE_META_FILE" || return 1
        lineage="$(cfip_rill_lineage_id)" || return 1
        cfip_rill_reset_holdout_cadence "$fingerprint" "$lineage"
        return $?
    fi
    if [[ "$stored" == "$fingerprint" ]]; then
        jq --arg fp "$fingerprint" '. + {currentContextFingerprint:$fp,contextTransitionPending:false}' <<<"$meta" | cfip_atomic_write "$CFIP_RILL_STATE_META_FILE"
        return $?
    fi
    stamp="$(date +%Y%m%d%H%M%S)"
    for file in "$CFIP_RILL_STATE" "$CFIP_RILL_QUALIFICATION_FILE" "$CFIP_RILL_HISTORY_FILE" "$CFIP_RILL_PREFIX_HISTORY_FILE" "$CFIP_RILL_COLO_HISTORY_FILE" "$CFIP_RILL_EVIDENCE_FILE"; do
        [[ -n "$file" && -e "$file" ]] || continue
        quarantine="${file}.quarantine.context.${stamp}"
        [[ -e "$quarantine" ]] && quarantine="${quarantine}.$$"
        mv "$file" "$quarantine" || return 1
    done
    if [[ -s "$CFIP_RILL_PENDING_FILE" ]] && jq -e 'type=="array"' "$CFIP_RILL_PENDING_FILE" >/dev/null 2>&1; then
        pending="$(jq --argjson at "$(date +%s)" 'map(. + {dueAt:0,rejectedReason:"context_changed",rejectedAt:$at})' "$CFIP_RILL_PENDING_FILE")"
        printf '%s\n' "$pending" | cfip_atomic_write "$CFIP_RILL_PENDING_FILE" || return 1
    fi
    cfip_rill_rotate_lineage context_changed || return 1
    lineage="$(cfip_rill_lineage_id)" || return 1
    cfip_rill_reset_holdout_cadence "$fingerprint" "$lineage" || return 1
    meta="$(cat "$CFIP_RILL_STATE_META_FILE" 2>/dev/null || printf '{}')"
    at="$(date +%s)"
    jq --arg fp "$fingerprint" --arg previous "$stored" --argjson context "$context" --argjson schema "$CFIP_RILL_CONTEXT_SCHEMA_VERSION" --argjson at "$at" \
      '. + {contextSchemaVersion:$schema,contextFingerprint:$fp,currentContextFingerprint:$fp,contextSummary:$context,previousContextFingerprint:$previous,contextChanged:true,contextChangedAt:$at,contextTransitionPending:false,resetRequired:false,resetReason:"context_changed"}' <<<"$meta" | cfip_atomic_write "$CFIP_RILL_STATE_META_FILE"
}

cfip_rill_prepare_state() {
    [[ -z "${CFIP_RILL_STATE:-}" ]] && return 0
    cfip_rill_context_guard || return 1
    mkdir -p "${CFIP_RILL_STATE%/*}"
    [[ ! -e "$CFIP_RILL_STATE" ]] && return 0
    local reason="" valid=true state_width
    jq -e --arg candidate "$CFIP_RILL_CANDIDATE_PARTITION_KEY" \
      '.formatVersion == 1 and (.partitions|type == "array") and ((.partitions|length) > 0) and all(.partitions[]?; .clientIdentityName != "cloudflare-ip" or .partitionKey == $candidate)' \
      "$CFIP_RILL_STATE" >/dev/null 2>&1 || valid=false
    if [[ "$valid" == true ]]; then
        state_width="$(jq -r --arg name cloudflare-ip --arg partition "$CFIP_RILL_PARTITION_KEY" \
          '([.partitions[]? | select(.clientIdentityName==$name and .partitionKey==$partition)][0].handlerSnapshot.state|implode|fromjson|.featureCount // 0)' \
          "$CFIP_RILL_STATE" 2>/dev/null || printf 0)"
        [[ "$state_width" == 0 || "$state_width" == 22 ]] || { valid=false; reason="feature_width_mismatch"; }
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

cfip_rill_evidence_json() {
    local max_bytes="${CFIP_RILL_EVIDENCE_MAX_BYTES:-262144}" bytes=0
    [[ "$max_bytes" =~ ^[1-9][0-9]*$ ]] || max_bytes=262144
    if [[ -e "$CFIP_RILL_EVIDENCE_FILE" ]]; then bytes="$(wc -c <"$CFIP_RILL_EVIDENCE_FILE")"; else bytes=0; fi
    if [[ -s "$CFIP_RILL_EVIDENCE_FILE" ]] && ((bytes <= max_bytes)) && jq -e --argjson limit "$CFIP_RILL_EVIDENCE_LIMIT" 'type=="array" and length<=$limit' "$CFIP_RILL_EVIDENCE_FILE" >/dev/null 2>&1; then
        cat "$CFIP_RILL_EVIDENCE_FILE"
    else
        [[ -s "$CFIP_RILL_EVIDENCE_FILE" ]] && mv "$CFIP_RILL_EVIDENCE_FILE" "${CFIP_RILL_EVIDENCE_FILE}.quarantine.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        printf '[]\n'
    fi
}

cfip_rill_write_evidence() {
    local input="$1" max_bytes="${CFIP_RILL_EVIDENCE_MAX_BYTES:-262144}" tmp next bytes count
    [[ "$max_bytes" =~ ^[1-9][0-9]*$ ]] || max_bytes=262144
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-evidence.XXXXXX")" || return 1
    cat "$input" >"$tmp" || { rm -f "$tmp"; return 1; }
    while :; do
        bytes="$(wc -c <"$tmp" 2>/dev/null || printf 0)"
        ((bytes <= max_bytes)) && break
        count="$(jq 'length' "$tmp" 2>/dev/null || printf 0)"
        if ((count <= 1)); then
            printf '[]\n' >"$tmp"
            break
        fi
        next="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-evidence-next.XXXXXX")" || { rm -f "$tmp"; return 1; }
        jq '.[1:]' "$tmp" >"$next" || { rm -f "$tmp" "$next"; return 1; }
        mv "$next" "$tmp"
    done
    cat "$tmp" | cfip_atomic_write "$CFIP_RILL_EVIDENCE_FILE"
    local rc=$?
    rm -f "$tmp"
    return "$rc"
}

cfip_rill_prefix_history_json() {
    [[ -s "$CFIP_RILL_PREFIX_HISTORY_FILE" ]] && jq -e 'type == "object"' "$CFIP_RILL_PREFIX_HISTORY_FILE" >/dev/null 2>&1 && cat "$CFIP_RILL_PREFIX_HISTORY_FILE" || printf '{}'
}

cfip_rill_colo_history_json() {
    [[ -s "$CFIP_RILL_COLO_HISTORY_FILE" ]] && jq -e 'type == "object" and (.entries|type=="object")' "$CFIP_RILL_COLO_HISTORY_FILE" >/dev/null 2>&1 && cat "$CFIP_RILL_COLO_HISTORY_FILE" || printf '{"schemaVersion":1,"entries":{},"unknownCount":0,"lastObserved":null}'
}

cfip_rill_update_prefix_history() {
    local observations="$1" now tmp
    [[ -s "$observations" ]] || return 0
    now="$(date +%s)"
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-prefix-history.XXXXXX")" || return 1
    cfip_rill_prefix_history_json | jq --argjson now "$now" --slurpfile rows "$observations" '
      def row: {samples:0,successes:0,failures:0,successRate:0.5,failureRate:0.5,latencySamples:[],ttfbSamples:[],lossSamples:[],throughputSamples:[],medianTotalMs:null,p95TotalMs:null,medianTtfbMs:null,lossRate:0.5,throughput:0,consecutiveFailures:0,lastSeen:0,rewardEWMA:0};
      def nums($a): ($a|map(select(type=="number" and isfinite)));
      def median($a): if ($a|length)>0 then $a|sort|.[((length-1)/2|floor)] else null end;
      def p95($a): if ($a|length)>0 then $a|sort|.[([((length*0.95)|floor),length-1]|min)] else null end;
      def ewma($old;$value): if ($value|type)!="number" then $old elif ($old|type)!="number" then $value else (0.8*$old+0.2*$value) end;
      reduce ($rows[0][]? | select((.prefixKey|type)=="string" and .prefixKey!="")) as $c (.;
        ($c.prefixKey) as $key | (.[$key] // row) as $old |
        (($c.eligible==true) and (($c.probeSummary.totalMs//null)|type=="number")) as $ok |
        ($c.probeSummary // {}) as $p |
        (($old.latencySamples + [($p.totalMs//null)|select(type=="number")])[-32:]|nums(.)) as $lat |
        (($old.ttfbSamples + [($p.ttfbMs//null)|select(type=="number")])[-32:]|nums(.)) as $ttfb |
        (($old.lossSamples + [($c.lossRate//null)|select(type=="number")])[-32:]|nums(.)) as $loss |
        (($old.throughputSamples + [($c.downloadMBps//null)|select(type=="number")])[-32:]|nums(.)) as $throughput |
        (if $ok then 0.5 else -0.5 end) as $reward |
        .[$key] = ($old + {samples:(($old.samples//0)+1),successes:(($old.successes//0)+(if $ok then 1 else 0 end)),failures:(($old.failures//0)+(if $ok then 0 else 1 end)),successRate:((($old.successes//0)+(if $ok then 1 else 0 end))/(($old.samples//0)+1)),failureRate:((($old.failures//0)+(if $ok then 0 else 1 end))/(($old.samples//0)+1)),latencySamples:$lat,ttfbSamples:$ttfb,lossSamples:$loss,throughputSamples:$throughput,medianTotalMs:median($lat),p95TotalMs:p95($lat),medianTtfbMs:median($ttfb),lossRate:(if ($loss|length)>0 then ($loss|add/length) else ($old.lossRate//0.5) end),throughput:(if ($throughput|length)>0 then ($throughput|add/length) else ($old.throughput//0) end),consecutiveFailures:(if $ok then 0 else (($old.consecutiveFailures//0)+1) end),lastSeen:$now,rewardEWMA:ewma($old.rewardEWMA;$reward)})
      ) | to_entries | sort_by(.value.lastSeen) | .[-256:] | from_entries
    ' >"$tmp" && cat "$tmp" | cfip_atomic_write "$CFIP_RILL_PREFIX_HISTORY_FILE"
    local rc=$?; rm -f "$tmp"; return "$rc"
}

cfip_rill_update_colo_history() {
    local observations="$1" now tmp
    [[ -s "$observations" ]] || return 0
    now="$(date +%s)"
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-colo-history.XXXXXX")" || return 1
    cfip_rill_colo_history_json | jq --argjson now "$now" --slurpfile rows "$observations" '
      def row: {samples:0,successes:0,failures:0,successRate:0.5,failureRate:0.5,latencySamples:[],ttfbSamples:[],lossSamples:[],throughputSamples:[],medianLatency:null,p95Latency:null,medianTtfb:null,loss:0.5,throughput:0,rewardEWMA:0,lastSeen:0};
      def nums($a): ($a|map(select(type=="number" and isfinite)));
      def median($a): if ($a|length)>0 then $a|sort|.[((length-1)/2|floor)] else null end;
      def p95($a): if ($a|length)>0 then $a|sort|.[([((length*0.95)|floor),length-1]|min)] else null end;
      def ewma($old;$value): if ($value|type)!="number" then $old elif ($old|type)!="number" then $value else (0.8*$old+0.2*$value) end;
      reduce ($rows[0][]?) as $c (.;
        ($c.colo|tostring|gsub("^[[:space:]]+|[[:space:]]+$";"")) as $colo |
        if ($colo=="" or $colo=="null" or ($c.colo|type)!="string") then .unknownCount=(.unknownCount//0)+1
        else ($c.probeSummary//{}) as $p | ($c.eligible==true and (($p.totalMs//null)|type=="number")) as $ok | (.entries[$colo] // row) as $old |
          (($old.latencySamples + [($p.totalMs//null)|select(type=="number")])[-32:]|nums(.)) as $lat |
          (($old.ttfbSamples + [($p.ttfbMs//null)|select(type=="number")])[-32:]|nums(.)) as $ttfb |
          (($old.lossSamples + [($c.lossRate//null)|select(type=="number")])[-32:]|nums(.)) as $loss |
          (($old.throughputSamples + [($c.downloadMBps//null)|select(type=="number")])[-32:]|nums(.)) as $throughput |
          (if $ok then 0.5 else -0.5 end) as $reward |
          .entries[$colo]=($old+{samples:(($old.samples//0)+1),successes:(($old.successes//0)+(if $ok then 1 else 0 end)),failures:(($old.failures//0)+(if $ok then 0 else 1 end)),successRate:((($old.successes//0)+(if $ok then 1 else 0 end))/(($old.samples//0)+1)),failureRate:((($old.failures//0)+(if $ok then 0 else 1 end))/(($old.samples//0)+1)),latencySamples:$lat,ttfbSamples:$ttfb,lossSamples:$loss,throughputSamples:$throughput,medianLatency:median($lat),p95Latency:p95($lat),medianTtfb:median($ttfb),loss:(if ($loss|length)>0 then ($loss|add/length) else ($old.loss//0.5) end),throughput:(if ($throughput|length)>0 then ($throughput|add/length) else ($old.throughput//0) end),rewardEWMA:ewma($old.rewardEWMA;$reward),lastSeen:$now}) | .lastObserved=$colo
        end
      ) | .schemaVersion=1 | .entries=(.entries|to_entries|sort_by(.value.lastSeen)|.[-128:]|from_entries)
    ' >"$tmp" && cat "$tmp" | cfip_atomic_write "$CFIP_RILL_COLO_HISTORY_FILE"
    local rc=$?; rm -f "$tmp"; return "$rc"
}

cfip_rill_reward_json() {
    local outcome="$1"
    jq -cn --argjson outcome "$(cat "$outcome")" '
      def n($v;$d): if ($v|type)=="number" and ($v|isfinite) then $v else $d end;
      def clamp($v;$lo;$hi): if $v < $lo then $lo elif $v > $hi then $hi else $v end;
      def mean($a;$d): if ($a|length)>0 then ($a|add/length) else $d end;
      def p95($a;$d): if ($a|length)>0 then $a|sort|.[([((length*0.95)|floor),length-1]|min)] else $d end;
      ($outcome.probes // []) as $probes |
      ($probes|map(select(.success==true))) as $ok |
      ($ok|map(n(.totalMs;10000))) as $totals |
      ($ok|map(n(.ttfbMs;10000))) as $ttfbs |
      (p95($totals;10000)) as $p95Total |
      ($probes|map(n(.lossRate;.candidateLossRate // 1))) as $losses |
      ($probes|map(n(.downloadMBps;.candidateDownloadMBps // 0))) as $throughputs |
      ($probes|group_by(.domain)|map({
        total:(map(n(.totalMs;10000))|max),
        ttfb:(map(n(.ttfbMs;10000))|max),
        loss:(map(n(.lossRate;.candidateLossRate // 1))|max)
      })) as $domains |
      (if ($domains|length)>0 then ($domains|map(.total)|max) else 10000 end) as $worstTotal |
      (if ($domains|length)>0 then ($domains|map(.ttfb)|max) else 10000 end) as $worstTtfb |
      (if ($domains|length)>0 then ($domains|map(.loss)|max) else 1 end) as $worstLoss |
      (if $outcome.candidateOutcome=="failure" then -1 else
        (0.25
         + 0.12*(1/(1+(mean($totals;10000)/1000)))
         + 0.08*(1/(1+($p95Total/1000)))
         + 0.15*(1/(1+(mean($ttfbs;10000)/1000)))
         + 0.20*(1-clamp($worstLoss;0;1))
         + 0.10*clamp((mean($throughputs;0)/100);0;1)
         + 0.10*clamp((n($outcome.delayedStability;.5));0;1)
         - 0.15*clamp(($worstTotal/10000);0;1)
         - 0.10*clamp(($worstTtfb/10000);0;1)) end) as $reward |
      {reward:clamp($reward;-1;1),rewardVersion:2,components:{
        success:(if $outcome.candidateOutcome=="success" then 0.25 else -1 end),
        latency:(0.12*(1/(1+(mean($totals;10000)/1000)))),
        p95:(0.08*(1/(1+($p95Total/1000)))),
        ttfb:(0.15*(1/(1+(mean($ttfbs;10000)/1000)))),
        loss:(0.20*(1-clamp($worstLoss;0;1))),
        throughput:(0.10*clamp((mean($throughputs;0)/100);0;1)),
        stability:(0.10*clamp((n($outcome.delayedStability;.5));0;1)),
        worstDomainPenalty:(-0.15*clamp(($worstTotal/10000);0;1)-0.10*clamp(($worstTtfb/10000);0;1))},
        worstDomain:{totalMs:$worstTotal,ttfbMs:$worstTtfb,lossRate:$worstLoss}}
    '
}

cfip_rill_reward_from_outcome() {
    cfip_rill_reward_json "$1" | jq -r '.reward'
}

cfip_rill_update_history() {
    local observations="$1" now tmp
    [[ -s "$observations" ]] || return 0
    now="$(date +%s)"
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-history.XXXXXX")" || return 1
    cfip_rill_history_json | jq --argjson now "$now" --slurpfile rows "$observations" '
      def row: {successCount:0,failureCount:0,latencySamples:[],ttfbSamples:[],lossSamples:[],throughputSamples:[],ewmaTotalMs:null,medianTotalMs:null,p95TotalMs:null,ewmaTtfbMs:null,ewmaLoss:null,lastSeen:0,lastSuccess:0,consecutiveFailures:0,lastSelected:false,previousWinner:false,prefixScore:0.5,sourceReliability:0.5,delayedStability:0.5};
      def nums($a): ($a|map(select(type=="number" and isfinite)));
      def median($a): if ($a|length)>0 then $a|sort|.[((length-1)/2|floor)] else null end;
      def p95($a): if ($a|length)>0 then $a|sort|.[([((length*0.95)|floor),length-1]|min)] else null end;
      def ewma($old;$value): if ($value|type)!="number" then $old elif ($old|type)!="number" then $value else (0.7*$old+0.3*$value) end;
      reduce ($rows[0][]? // {}) as $c (.;
        ($c.ip|tostring) as $id |
        (.[$id] // row) as $old |
        (($c.eligible == true) and (($c.probeSummary.totalMs // null)|type == "number")) as $ok |
        (($old.latencySamples + [($c.probeSummary.totalMs // null)|select(type=="number")])[-32:] | nums(.)) as $samples |
        (($old.ttfbSamples + [($c.probeSummary.ttfbMs // null)|select(type=="number")])[-32:] | nums(.)) as $ttfb |
        (($old.lossSamples + [($c.lossRate // null)|select(type=="number")])[-32:] | nums(.)) as $loss |
        (($old.throughputSamples + [($c.downloadMBps // null)|select(type=="number")])[-32:] | nums(.)) as $throughput |
        .[$id] = ($old + {
          successCount: (($old.successCount // 0) + (if $ok then 1 else 0 end)),
          failureCount: (($old.failureCount // 0) + (if $ok then 0 else 1 end)),
          latencySamples: $samples,
          ttfbSamples: $ttfb,
          lossSamples: $loss,
          throughputSamples: $throughput,
          ewmaTotalMs: ewma($old.ewmaTotalMs; $c.probeSummary.totalMs),
          medianTotalMs: median($samples),
          p95TotalMs: p95($samples),
          ewmaTtfbMs: ewma($old.ewmaTtfbMs; $c.probeSummary.ttfbMs),
          ewmaLoss: ewma($old.ewmaLoss; $c.lossRate),
          prefixScore: (if $ok then 0.7*($old.prefixScore//0.5)+0.3 else 0.7*($old.prefixScore//0.5) end),
          sourceReliability: (if $ok then 0.7*($old.sourceReliability//0.5)+0.3 else 0.7*($old.sourceReliability//0.5) end),
          lastSeen: $now,
          lastSuccess: (if $ok then $now else ($old.lastSuccess // 0) end),
          consecutiveFailures: (if $ok then 0 else (($old.consecutiveFailures // 0)+1) end),
          delayedStability: (if $ok then 0.8*($old.delayedStability//0.5)+0.2 else 0.8*($old.delayedStability//0.5) end)
        })
      ) | to_entries | sort_by(.value.lastSeen) | .[-256:] | from_entries
    ' >"$tmp" && cat "$tmp" | cfip_atomic_write "$CFIP_RILL_HISTORY_FILE"
    local rc=$?; rm -f "$tmp"
    cfip_rill_update_prefix_history "$observations" || cfip_log "prefix history update deferred"
    cfip_rill_update_colo_history "$observations" || cfip_log "colo history update deferred"
    return "$rc"
}

cfip_rill_probe_priority() {
    local input="$1" output="$2" history prefix_history colo_history
    [[ -s "$input" ]] || { printf '[]\n' | cfip_atomic_write "$output"; return 0; }
    if [[ "${CFIP_RILL_ENABLED:-false}" != true || "${CFIP_RILL_MODE:-off}" == off ]]; then
        cat "$input" | cfip_atomic_write "$output"
        return $?
    fi
    history="$(cfip_rill_history_json)"; prefix_history="$(cfip_rill_prefix_history_json)"; colo_history="$(cfip_rill_colo_history_json)"
    jq --argjson history "$history" --argjson prefixHistory "$prefix_history" --argjson coloHistory "$colo_history" --argjson now "$(date +%s)" '
      map((.ip|tostring) as $id |
        (($history[$id].successCount//0)+($history[$id].failureCount//0)) as $samples |
        (($history[$id].successCount//0) / ($samples+1)) as $prior |
        ((($history[$id].ewmaTotalMs // 10000) / 10000) | if . < 0 then 0 elif . > 1 then 1 else . end) as $latency |
        ((($history[$id].sourceReliability // .sourceReliability // 0.5))|if .<0 then 0 elif .>1 then 1 else . end) as $source |
        ($prefixHistory[(.prefixKey // "")] // {}) as $prefix |
        (if (($prefix.samples//0)>0) then
          ([1-(($now-($prefix.lastSeen//0))/604800),0]|max) as $freshness |
          (0.5 + ((($prefix.successRate//0.5)-0.5) * $freshness) - ([($prefix.consecutiveFailures//0),3]|min)*0.05*$freshness)
        else 0.5 end) as $prefixScore |
        ($coloHistory.entries[(.colo|tostring)] // {}) as $colo |
        (if (($colo.samples//0)>0) then ($colo.successRate//0.5) else 0.5 end) as $coloScore |
        . + {prefixHistoryScore:$prefixScore,coloQuality:$coloScore,probePriority:(0.30*$prior + 0.20*(1-$latency) + 0.15*$source + 0.15*$prefixScore + 0.10*$coloScore + 0.10*(1-((.cfstRank//128)/128)))}
      ) | sort_by(-.probePriority,($history[(.ip|tostring)].consecutiveFailures//0),(.cfstRank//999999),(.ip|tostring))
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
          '{state:"cold",validFeedback:0,attributedFeedback:0,delayedCompleted:0,delayedExpired:0,delayedRejected:0,disagreements:0,disagreementWin:0,disagreementLoss:0,disagreementTie:0,disagreementWinRate:null,errors:0,candidateFailures:0,recentRewards:[],window:[],trainingWindow:[],evaluationWindow:[],legacyEvaluationCompatibility:true,lastReward:null,rollingReward:null,nativeReward:null,rillReward:null,rewardDelta:null,shadowRegret:0,minFeedbackSamples:$minimum,minDisagreementSamples:10,trainingHealth:"cold",evaluationHealth:"insufficient",evaluationFreshAt:null,lastDecisionConfidenceLevel:null,lastDecisionConfidenceReasons:[],updatedAt:null}'
    fi
}

cfip_rill_qualified() {
    local current state health latest max_age now
    current="$(cfip_rill_qualification_json)"
    state="$(jq -r '.state // "cold"' <<<"$current")"
    health="$(jq -r '.evaluationHealth // "insufficient"' <<<"$current")"
    [[ "$state" == shadow-qualified || "$state" == guarded-assisted ]] && [[ "$health" == healthy ]] || return 1
    latest="$(jq -r '.evaluationFreshAt // ([.evaluationWindow[]?|select(.comparisonResult=="win" or .comparisonResult=="tie" or .comparisonResult=="loss")|.at]|max // 0)' <<<"$current")"
    max_age="${CFIP_RILL_EVALUATION_MAX_AGE_SECONDS:-86400}"; [[ "$max_age" =~ ^[1-9][0-9]*$ ]] || max_age=86400
    now="$(cfip_rill_now_seconds)"
    [[ "$latest" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] && ((latest>0 && now-latest<=max_age))
}

cfip_rill_assisted_ready() {
    local status schema
    status="$(cfip_rill_status_json 2>/dev/null || true)"; schema="$(cfip_rill_schema_hash 2>/dev/null || true)"
    [[ -n "$schema" ]] || return 1
    jq -e --arg schema "$schema" '(.available==true and .state=="healthy" and .health=="healthy" and .healthHealthy==true and .resourcePressure==false and .featureSchemaVersion==2 and .modelGeneration==2 and .featureSchemaHash==$schema and (.qualificationState=="shadow-qualified" or .qualificationState=="guarded-assisted") and .resetRequired==false and (.contextTransitionPending // false)==false)' <<<"$status" >/dev/null 2>&1
}

cfip_rill_record_qualification() {
    local candidate_outcome="$1" attribution="$2" delayed="$3" error="$4" reward="${5:-}" outcome_file="${6:-}" current state count attributed completed errors failures delayed_expired delayed_rejected minimum recent_rewards training_window evaluation_window native_reward rill_reward delta disagreement legacy_evaluation=false
    current="$(cfip_rill_qualification_json)"
    state="$(jq -r '.state // "cold"' <<<"$current")"
    count="$(jq -r '.validFeedback // 0' <<<"$current")"; attributed="$(jq -r '.attributedFeedback // 0' <<<"$current")"
    completed="$(jq -r '.delayedCompleted // 0' <<<"$current")"; delayed_expired="$(jq -r '.delayedExpired // 0' <<<"$current")"; delayed_rejected="$(jq -r '.delayedRejected // 0' <<<"$current")"; errors="$(jq -r '.errors // 0' <<<"$current")"; failures="$(jq -r '.candidateFailures // 0' <<<"$current")"
    recent_rewards="$(jq -c '.recentRewards // []' <<<"$current")"
    training_window="$(jq -c '.trainingWindow // .window // []' <<<"$current")"
    if jq -e 'has("evaluationWindow")' <<<"$current" >/dev/null 2>&1; then evaluation_window="$(jq -c '.evaluationWindow // []' <<<"$current")"; [[ "$(jq -r '.legacyEvaluationCompatibility // false' <<<"$current")" == true ]] && legacy_evaluation=true; else evaluation_window="$(jq -c '.window // []' <<<"$current")"; legacy_evaluation=true; fi
    minimum="${CFIP_RILL_MIN_FEEDBACK_SAMPLES:-30}"
    [[ "$candidate_outcome" == success || "$candidate_outcome" == failure ]] && count=$((count+1))
    [[ "$candidate_outcome" == failure ]] && failures=$((failures+1))
    [[ "$attribution" == true ]] && attributed=$((attributed+1))
    [[ "$delayed" == true ]] && completed=$((completed+1))
    [[ "$error" == true ]] && errors=$((errors+1))
    if [[ "$reward" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        recent_rewards="$(jq -cn --argjson a "$recent_rewards" --argjson reward "$reward" '($a+[$reward])[-32:]')"
    fi
    if [[ -n "$outcome_file" && -s "$outcome_file" ]]; then
        native_reward="$(jq -r '.nativeCounterfactualReward // .nativeReward // empty' "$outcome_file" 2>/dev/null || true)"
        rill_reward="$(jq -r '.rillShadowReward // .reward // empty' "$outcome_file" 2>/dev/null || true)"
        delta="$(jq -r '.rewardDelta // empty' "$outcome_file" 2>/dev/null || true)"
        disagreement="$(jq -r 'if .disagreement==true then true else false end' "$outcome_file" 2>/dev/null || printf false)"
        [[ "$native_reward" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || native_reward=null
        [[ "$rill_reward" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || rill_reward=null
        [[ "$delta" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || delta=null
        training_window="$(jq -cn --argjson w "$training_window" --arg outcome "$candidate_outcome" --argjson attributed "$attribution" --argjson delayed "$delayed" --argjson error "$error" --argjson reward "${reward:-null}" '($w+[{evidenceType:"training",candidateOutcome:$outcome,attributed:$attributed,delayed:$delayed,error:$error,reward:$reward,at:(now|floor)}])[-64:]')"
        # Legacy qualification files may have carried evaluation fields in the
        # old combined window. New files receive evaluation only from the
        # explicit record_evaluation path below.
        if [[ "$disagreement" == true && "$legacy_evaluation" == true ]]; then
            evaluation_window="$(jq -cn --argjson w "$evaluation_window" --argjson native "$native_reward" --argjson rill "$rill_reward" --argjson delta "$delta" '($w+[{evaluationSource:"shadow",nativeReward:$native,rillReward:$rill,rewardDelta:$delta,comparisonResult:(if ($delta|type)!="number" then "unavailable" elif $delta>0.02 then "win" elif $delta < -0.02 then "loss" else "tie" end),at:(now|floor)}])[-64:]')"
        fi
    fi
    local training_count training_attributed training_delayed training_errors eval_count wins losses ties mean_delta severe eval_healthy training_healthy was_qualified epsilon latest_eval max_age eval_health
    epsilon="${CFIP_RILL_REWARD_TIE_EPSILON:-0.02}"
    training_count="$(jq 'length' <<<"$training_window")"; training_attributed="$(jq '[.[]|select(.attributed==true)]|length' <<<"$training_window")"; training_delayed="$(jq '[.[]|select(.delayed==true)]|length' <<<"$training_window")"; training_errors="$(jq '[.[]|select(.error==true)]|length' <<<"$training_window")"
    eval_count="$(jq '[.[]|select(.comparisonResult=="win" or .comparisonResult=="tie" or .comparisonResult=="loss")]|length' <<<"$evaluation_window")"; wins="$(jq --argjson epsilon "$epsilon" '[.[]|select((.comparisonResult=="win") or ((.rewardDelta|type)=="number" and .rewardDelta>$epsilon))]|length' <<<"$evaluation_window")"; losses="$(jq --argjson epsilon "$epsilon" '[.[]|select((.comparisonResult=="loss") or ((.rewardDelta|type)=="number" and .rewardDelta<(-$epsilon))) ]|length' <<<"$evaluation_window")"; ties="$(jq --argjson epsilon "$epsilon" '[.[]|select((.comparisonResult=="tie") or ((.rewardDelta|type)=="number" and .rewardDelta>=(-$epsilon) and .rewardDelta<=$epsilon))]|length' <<<"$evaluation_window")"
    mean_delta="$(jq -r '[.[]|select(.rewardDelta|type=="number")|.rewardDelta] | if length>0 then add/length else null end' <<<"$evaluation_window")"; severe="$(jq '[.[]|select((.rewardDelta|type)=="number" and .rewardDelta < -0.25)]|length' <<<"$evaluation_window")"
    training_healthy=false; ((count >= minimum && training_count > 0 && training_attributed == training_count && training_delayed * 100 >= training_count * 80 && training_errors * 100 <= (training_count*5))) && training_healthy=true
    latest_eval="$(jq -r '[.[]|select((.comparisonResult=="win" or .comparisonResult=="tie" or .comparisonResult=="loss") and (.at|type)=="number")|.at]|max // 0' <<<"$evaluation_window")"
    max_age="${CFIP_RILL_EVALUATION_MAX_AGE_SECONDS:-86400}"; [[ "$max_age" =~ ^[1-9][0-9]*$ ]] || max_age=86400
    eval_healthy=false; ((eval_count >= 10 && severe * 100 <= (eval_count*10))) && eval_healthy=true; if [[ "$mean_delta" != null ]] && awk -v x="$mean_delta" 'BEGIN { exit !(x < -0.05) }'; then eval_healthy=false; fi
    if ((eval_count==0)); then eval_health=cold
    elif ((eval_count<10)); then eval_health=insufficient
    elif ((severe * 100 > eval_count * 10)) || { [[ "$mean_delta" != null ]] && awk -v x="$mean_delta" 'BEGIN { exit !(x < -0.05) }'; }; then eval_health=negative
    elif ((latest_eval>0)) && (( $(cfip_rill_now_seconds) - latest_eval > max_age )); then eval_health=stale
    elif [[ "$eval_healthy" == true ]]; then eval_health=healthy
    else eval_health=insufficient; fi
    [[ "$eval_health" == healthy ]] || eval_healthy=false
    was_qualified=false; [[ "$state" == guarded-assisted || "$state" == shadow-qualified ]] && was_qualified=true
    [[ "$state" == reset-required ]] || {
        if [[ "$training_healthy" == true && "$eval_healthy" == true ]]; then state=shadow-qualified
        elif [[ "$was_qualified" == true || "$state" == shadow ]]; then state=shadow
        elif ((count > 0)); then state=learning
        else state=cold; fi
    }
    jq -cn --arg state "$state" --arg evalHealth "$eval_health" --argjson maxAge "$max_age" --argjson freshAt "$latest_eval" --argjson count "$count" --argjson attributed "$attributed" \
      --argjson completed "$completed" --argjson expired "$delayed_expired" --argjson rejected "$delayed_rejected" --argjson errors "$errors" --argjson failures "$failures" --argjson rewards "$recent_rewards" --argjson minimum "$minimum" --argjson training "$training_window" --argjson evaluation "$evaluation_window" --argjson legacyEvaluation "$legacy_evaluation" --argjson evalCount "$eval_count" --argjson dis "$eval_count" --argjson wins "$wins" --argjson losses "$losses" --argjson ties "$ties" --argjson meanDelta "$mean_delta" --argjson severe "$severe" --argjson trainingErrors "$training_errors" --arg trainingHealth "$(if [[ "$training_healthy" == true ]]; then printf healthy; else printf insufficient; fi)" --arg evaluationHealth "$eval_health" \
      '{state:$state,validFeedback:$count,attributedFeedback:$attributed,delayedCompleted:$completed,delayedExpired:$expired,delayedRejected:$rejected,errors:$errors,candidateFailures:$failures,recentRewards:$rewards,window:$training,trainingWindow:$training,evaluationWindow:$evaluation,legacyEvaluationCompatibility:$legacyEvaluation,lastReward:($rewards[-1] // null),rollingReward:(if ($rewards|length)>0 then ($rewards|add/length) else null end),nativeReward:($evaluation|map(select(.nativeReward|type=="number")|.nativeReward)|if length>0 then add/length else null end),rillReward:($evaluation|map(select(.rillReward|type=="number")|.rillReward)|if length>0 then add/length else null end),rewardDelta:$meanDelta,shadowRegret:($evaluation|map(select((.rewardDelta|type=="number") and .rewardDelta<0)|-.rewardDelta)|add//0),disagreements:$dis,disagreementWin:$wins,disagreementLoss:$losses,disagreementTie:$ties,disagreementWinRate:(if $dis>0 then $wins/$dis else null end),recentWindowErrors:$trainingErrors,windowSize:($training|length),trainingWindowSize:($training|length),evaluationWindowSize:($evaluation|length),evaluationCount:$evalCount,severeRegressionCount:$severe,trainingHealth:$trainingHealth,evaluationHealth:$evalHealth,minFeedbackSamples:$minimum,minDisagreementSamples:10,evaluationFreshAt:(if $freshAt==0 then null else $freshAt end),evaluationMaxAgeSeconds:$maxAge,updatedAt:(now|floor)}' \
      | cfip_atomic_write "$CFIP_RILL_QUALIFICATION_FILE"
}

cfip_rill_pending_count() {
    [[ -s "$CFIP_RILL_PENDING_FILE" ]] && jq 'length' "$CFIP_RILL_PENDING_FILE" 2>/dev/null || printf 0
}

cfip_rill_quarantine_pending_queue() {
    local stamp quarantine
    stamp="$(date +%Y%m%d%H%M%S)"
    quarantine="${CFIP_RILL_PENDING_FILE}.quarantine.${stamp}"
    [[ -e "$quarantine" ]] && quarantine="${quarantine}.$$"
    mv "$CFIP_RILL_PENDING_FILE" "$quarantine" || return 1
    printf '[]\n' | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"
    cfip_log "Rill pending queue quarantined: invalid_or_corrupt ($quarantine)"
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

cfip_rill_health_json() {
    local schema request response
    schema="$(cfip_rill_schema_hash 2>/dev/null || true)"; [[ -n "$schema" ]] || return 1
    request="$(jq -cn --arg id "health-${CFIP_RUN_ID:-status}" --arg schema "$schema" --arg partition "$CFIP_RILL_PARTITION_KEY" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},partitionKey:$partition,featureSchemaHash:$schema,modelGeneration:2,stateGeneration:0,payloadLimit:1048576,request:{method:"health"}}')"
    response="$(cfip_rill_runtime_call "$request" 2>/dev/null || true)"
    jq -e '.response.kind=="health" and (.response.status|type)=="string"' <<<"$response" >/dev/null 2>&1 || return 1
    printf '%s' "$response"
}

cfip_rill_status_json() {
    local request response health inspect schema qualification meta history pending health_status health_ok resource_pressure resource_reason_codes partition context aggregate
    partition="$CFIP_RILL_CANDIDATE_PARTITION_KEY"
    if [[ "${CFIP_RILL_ENABLED:-false}" != true || "${CFIP_RILL_MODE:-off}" == off ]]; then
        jq -cn --arg partition "$partition" '{available:false,state:"disabled",mode:"off",channel:"preview",partitionKey:$partition,featureSchemaVersion:2,modelGeneration:2}'
        return 0
    fi
    schema="$(cfip_rill_schema_hash 2>/dev/null || true)"
    [[ -n "$schema" ]] || { jq -cn --arg mode "$CFIP_RILL_MODE" --arg partition "$partition" '{available:false,state:"schema-unavailable",mode:$mode,partitionKey:$partition}'; return 0; }
    request="$(jq -cn --arg id "status-${CFIP_RUN_ID:-status}" --arg schema "$schema" --arg partition "$CFIP_RILL_PARTITION_KEY" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},partitionKey:$partition,featureSchemaHash:$schema,modelGeneration:2,stateGeneration:0,payloadLimit:1048576,request:{method:"handshake"}}')"
    response="$(cfip_rill_runtime_call "$request" 2>/dev/null || true)"
    qualification="$(cfip_rill_qualification_json)"; meta='{}'; [[ -s "$CFIP_RILL_STATE_META_FILE" ]] && meta="$(cat "$CFIP_RILL_STATE_META_FILE")"; context="$(cfip_rill_context_json 2>/dev/null || printf '{}')"; aggregate="$(cfip_rill_evidence_aggregate_json 2>/dev/null || printf '{}')"
    history="$(cfip_rill_history_json)"; pending="$(cfip_rill_pending_count)"
    if jq -e --arg id "status-${CFIP_RUN_ID:-status}" --arg schema "$schema" \
      '.requestId==$id and .response.kind=="handshake" and .apiVersion==3 and (.response.capabilities|type=="array") and .response.featureSchemaHash==$schema and (.response.capabilities|index("org.rill.preview.decide")) and (.response.capabilities|index("org.rill.preview.feedback")) and .response.handlerApiVersion==2' <<<"$response" >/dev/null 2>&1; then
        health="$(cfip_rill_health_json 2>/dev/null || printf '{}')"
        inspect="$(cfip_rill_inspect_json 2>/dev/null || printf '{}')"
        health_status="$(jq -r '.response.status // "unknown"' <<<"$health")"
        health_ok="$(jq -r '.response.healthy // false' <<<"$health")"
        # The Preview health response is intentionally small. Inspect is the
        # authoritative resource contract: pressure is true at 90% of any
        # bounded state/pending/completed counter, or when health says so.
        resource_pressure="$(jq -r '
          def near($used;$limit): (($limit|type)=="number" and $limit>0 and ($used|type)=="number" and ($used*10 >= $limit*9));
          ((.response.status=="resource_pressure") or any(.response.reasonCodes[]?; .=="resource_pressure"))' <<<"$health")"
        if [[ "$resource_pressure" != true ]]; then
            resource_pressure="$(jq -r '
              def near($used;$limit): (($limit|type)=="number" and $limit>0 and ($used|type)=="number" and ($used*10 >= $limit*9));
              (near(.resourceUtilization.stateBytes;.resourceProfile.maxModelStateBytes)
               or near(.resourceUtilization.pendingDecisions;.resourceProfile.maxPendingDecisions)
               or near(.resourceUtilization.completedDecisions;.resourceProfile.maxCompletedDecisions))' <<<"$inspect")"
        fi
        [[ "$resource_pressure" == true ]] && health_status=resource_pressure
        resource_reason_codes="$(jq -c --argjson pressure "$resource_pressure" '(.response.reasonCodes // []) + (if $pressure then ["resource_pressure"] else [] end) | unique' <<<"$health")"
        jq -cn --arg mode "$CFIP_RILL_MODE" --arg partition "$partition" --arg schema "$schema" --argjson s "$response" --argjson health "$health" --argjson inspect "$inspect" --argjson q "$qualification" --argjson m "$meta" --argjson h "$history" --argjson pending "$pending" --argjson context "$context" --argjson aggregate "$aggregate" --arg healthStatus "$health_status" --argjson healthOk "$health_ok" --argjson resourcePressure "$resource_pressure" --argjson resourceReasonCodes "$resource_reason_codes" \
          '{available:true,state:(if $resourcePressure or ($healthOk|not) then "degraded" else "healthy" end),channel:($s.response.channel//"preview"),partitionKey:$partition,mode:$mode,runtimeVersion:$s.runtimeIdentity.version,runtimeApiVersion:$s.apiVersion,capabilities:$s.response.capabilities,featureSchemaVersion:2,featureSchemaHash:$schema,modelGeneration:$s.modelGeneration,stateGeneration:$s.stateGeneration,handlerApiVersion:$s.response.handlerApiVersion,health:$healthStatus,healthHealthy:($healthOk and ($resourcePressure|not)),healthReasonCodes:$resourceReasonCodes,qualificationState:(if $m.resetRequired==true then "reset-required" else ($q.state//"cold") end),validFeedback:($q.validFeedback//0),attributedFeedback:($q.attributedFeedback//0),delayedCompleted:($q.delayedCompleted//0),delayedExpired:($q.delayedExpired//0),delayedRejected:($q.delayedRejected//0),candidateFailures:($q.candidateFailures//0),trainingHealth:($q.trainingHealth//"unknown"),evaluationHealth:($q.evaluationHealth//"insufficient"),trainingWindowSize:($q.trainingWindowSize//($q.window|length)),evaluationWindowSize:($q.evaluationWindowSize//($q.evaluationWindow|length)),evaluationCount:($q.evaluationCount//0),lastReward:($q.lastReward//null),rollingReward:($q.rollingReward//null),nativeReward:($q.nativeReward//null),rillReward:($q.rillReward//null),rewardDelta:($q.rewardDelta//null),shadowRegret:($q.shadowRegret//0),disagreements:($q.disagreements//0),disagreementWinRate:($q.disagreementWinRate//null),pendingDelayedFeedback:$pending,candidateHistoryCount:($h|length),lastResetReason:($m.resetReason//null),resetRequired:($m.resetRequired//false),resourcePressure:$resourcePressure,inspect:$inspect,learningContext:$context,evidenceAggregate:$aggregate,contextChangedAt:($m.contextChangedAt//null),contextChanged:($m.contextChanged//false),contextTransitionPending:($m.contextTransitionPending//false),contextLineageId:($m.lineageId//null),confidenceLevel:($q.lastDecisionConfidenceLevel//null),confidenceReasons:($q.lastDecisionConfidenceReasons//[])}'
    else
        jq -cn --arg mode "$CFIP_RILL_MODE" --arg partition "$partition" --argjson q "$qualification" --argjson m "$meta" --argjson pending "$pending" --argjson context "$context" --argjson aggregate "$aggregate" \
          '{available:false,state:"incompatible",channel:"preview",partitionKey:$partition,mode:$mode,runtimeApiVersion:3,featureSchemaVersion:2,modelGeneration:2,qualificationState:(if $m.resetRequired==true then "reset-required" else $q.state end),pendingDelayedFeedback:$pending,lastResetReason:($m.resetReason//null),resetRequired:($m.resetRequired//false),learningContext:$context,evidenceAggregate:$aggregate,contextChangedAt:($m.contextChangedAt//null),contextChanged:($m.contextChanged//false),contextTransitionPending:($m.contextTransitionPending//false),contextLineageId:($m.lineageId//null),confidenceLevel:($q.lastDecisionConfidenceLevel//null),confidenceReasons:($q.lastDecisionConfidenceReasons//[])}'
    fi
}

cfip_rill_actions_json() {
    local history prefix_history now
    history="$(cfip_rill_history_json)"; prefix_history="$(cfip_rill_prefix_history_json)"; now="$(date +%s)"
    jq -c --argjson history "$history" --argjson prefixHistory "$prefix_history" --argjson now "$now" '
      def n($v;$fallback): if ($v|type)=="number" and ($v|isfinite) then $v else $fallback end;
      def clamp($v;$fallback;$lo;$hi): (n($v;$fallback) | if . < $lo then $lo elif . > $hi then $hi else . end);
      def ms($v): clamp($v;10000;0;10000)/10000;
      def samples($v): (($v|map(select(type=="number"))|sort) // []);
      [.[] as $candidate |
        ($history[($candidate.ip|tostring)] // {}) as $h |
        ($prefixHistory[($candidate.prefixKey // "")] // {}) as $ph |
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
          (if $h.lastSelected==true then 1 else 0 end),
          (if (($ph.samples//0)>0) then
            ([1-(($now-($ph.lastSeen//0))/604800),0]|max) as $freshness |
            clamp((0.5 + ((($ph.successRate//0.5)-0.5) * $freshness) - ([($ph.consecutiveFailures//0),3]|min)*0.05*$freshness);0.5;0;1)
           else 0.5 end)
        ]}]
    ' "$1"
}

cfip_rill_rank_shadow() (
    local native_json="$1" output="$2" request tmp rc=0 response_bytes native_set rill_set schema actions selected_id generation scores
    [[ "${CFIP_RILL_ENABLED:-false}" == true && "${CFIP_RILL_MODE:-off}" != off ]] || return 2
    [[ -x "$CFIP_RILL_RUNTIME" ]] || return 3
    CFIP_RILL_PARTITION_KEY="$CFIP_RILL_CANDIDATE_PARTITION_KEY"
    cfip_rill_prepare_state || return 10
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
    jq --arg selected "$selected_id" --arg partition "$CFIP_RILL_PARTITION_KEY" --arg generation "$generation" --argjson candidates "$(cat "$native_json")" --argjson scores "$scores" \
      '{success:true,decisionKind:"candidate",partitionKey:$partition,decisionId:.requestId,selectedActionId:$selected,generation:($generation|tonumber),candidates:($candidates|map(. as $c | ($scores|to_entries|map(select(.value.id==($c.ip|tostring)))[0]) as $s | $c + {rillScore:($s.value.score//null),rillRank:(if $s then ($s.key+1) else null end),scoreMargin:(if $s and $scores[($s.key+1)] then ($s.value.score-$scores[($s.key+1)].score) else null end)}) | sort_by(.rillRank // 99999)),runtimeApiVersion:.apiVersion,shadowCandidateInvariant:true}' "$tmp" >"$output"
    rm -f "$tmp"
)

cfip_rill_shadow_observe() {
    local decision="$1" rill="$2" domains="$3" timeout_s="$4" output="$5" native_outcome="${6:-}" selected candidate probe all_ok=true probes='[]' domain family tmp reward_json native_reward=null rill_reward disagreement=false probe_rc=0 expected_domains=0
    selected="$(jq -r '.selectedActionId // empty' "$decision")"; [[ -n "$selected" ]] || return 2
    candidate="$(jq -c --arg id "$selected" '.candidates[]|select((.ip|tostring)==$id)' "$rill" | head -n1)"; [[ -n "$candidate" ]] || return 2
    family="$(jq -r '.family' <<<"$candidate")"; IFS=',' read -r -a domain_list <<<"$domains"; expected_domains="${#domain_list[@]}"
    for domain in "${domain_list[@]}"; do
        [[ -n "$domain" ]] || continue
        probe_rc=0; probe="$(cfip_probe_one "$selected" "$domain" "$family" "$timeout_s")" || probe_rc=$?
        ((probe_rc==0)) || return 1
        jq -e 'type=="object" and (.ip|type)=="string" and (.domain|type)=="string" and (.success|type)=="boolean" and (.connectMs|type)=="number" and (.tlsMs|type)=="number" and (.ttfbMs|type)=="number" and (.totalMs|type)=="number"' <<<"$probe" >/dev/null 2>&1 || return 1
        probes="$(jq -cn --argjson a "$probes" --argjson p "$probe" --argjson loss "$(jq -r '.lossRate // 1' <<<"$candidate")" --argjson throughput "$(jq -r '.downloadMBps // 0' <<<"$candidate")" '$a+[$p+{lossRate:$loss,downloadMBps:$throughput}]')"; [[ "$(jq -r '.success' <<<"$probe")" == true ]] || all_ok=false
    done
    (( $(jq 'length' <<<"$probes") == expected_domains && expected_domains > 0 )) || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-shadow-outcome.XXXXXX")" || return 1
    jq -cn --arg runId "${CFIP_RUN_ID:-}" --arg ip "$selected" --arg decisionId "$(jq -r '.decisionId' "$decision")" --argjson ok "$all_ok" --argjson probes "$probes" \
      '{schemaVersion:2,runId:$runId,decisionId:$decisionId,validated:$ok,candidateOutcome:(if $ok then "success" else "failure" end),hostOutcome:"success",censored:false,observedIp:$ip,decisionActionId:$ip,probes:$probes}' >"$tmp"
    reward_json="$(cfip_rill_reward_json "$tmp")"; rill_reward="$(jq -r '.reward' <<<"$reward_json")"
    if [[ -n "$native_outcome" && -s "$native_outcome" ]]; then native_reward="$(cfip_rill_reward_from_outcome "$native_outcome" 2>/dev/null || printf null)"; fi
    [[ "$(jq -r '.observedIp // empty' "$native_outcome" 2>/dev/null || true)" == "$selected" ]] || disagreement=true
    jq --argjson reward "$reward_json" --argjson native "$native_reward" --argjson disagreement "$disagreement" --argjson epsilon "${CFIP_RILL_REWARD_TIE_EPSILON:-0.02}" \
      '. + {reward:$reward.reward,rewardVersion:$reward.rewardVersion,rewardComponents:$reward.components,worstDomain:$reward.worstDomain,rillShadowReward:$reward.reward,nativeCounterfactualReward:(if ($native|type)=="number" then $native else null end),rewardDelta:(if ($native|type)=="number" then ($reward.reward-$native) else null end),comparison:(if ($native|type)!="number" then "unavailable" elif ($reward.reward-$native)>$epsilon then "win" elif ($reward.reward-$native)<(-$epsilon) then "loss" else "tie" end),disagreement:$disagreement}' "$tmp" | cfip_atomic_write "$output"
    rm -f "$tmp"
}

cfip_rill_holdout_due() {
    local decision="$1" interval count native authority fingerprint lineage cadence decision_id last_decision
    [[ "$(jq -r '.effectiveMode // empty' "$decision" 2>/dev/null)" == assisted ]] || return 1
    native="$(jq -r '.nativeOrder[0] // empty' "$decision" 2>/dev/null)"
    authority="$(jq -r '.authorityActionId // empty' "$decision" 2>/dev/null)"
    [[ -n "$native" && -n "$authority" && "$native" != "$authority" ]] || return 1
    interval="${CFIP_RILL_HOLDOUT_INTERVAL:-5}"
    [[ "$interval" =~ ^[1-9][0-9]*$ ]] || interval=5
    fingerprint="$(cfip_rill_context_fingerprint 2>/dev/null || printf '')"; lineage="$(cfip_rill_lineage_id 2>/dev/null || printf '')"
    decision_id="$(jq -r '.decisionId // empty' "$decision" 2>/dev/null || printf '')"
    [[ -n "$decision_id" ]] || decision_id="$(sha256sum "$decision" | awk '{print $1}')"
    cadence='{}'
    [[ -s "$CFIP_RILL_HOLDOUT_STATE_FILE" ]] && cadence="$(jq -c 'if type=="object" then . else {} end' "$CFIP_RILL_HOLDOUT_STATE_FILE" 2>/dev/null || printf '{}')"
    if [[ "$(jq -r '.contextFingerprint // empty' <<<"$cadence")" != "$fingerprint" || "$(jq -r '.stateLineage // empty' <<<"$cadence")" != "$lineage" ]]; then
        cadence="$(jq -cn --arg fp "$fingerprint" --arg lineage "$lineage" '{schemaVersion:1,contextFingerprint:$fp,stateLineage:$lineage,assistedDisagreementCount:0,lastDecisionId:null}')"
    fi
    count="$(jq -r '.assistedDisagreementCount // 0' <<<"$cadence")"; [[ "$count" =~ ^[0-9]+$ ]] || count=0
    last_decision="$(jq -r '.lastDecisionId // empty' <<<"$cadence")"
    if [[ "$last_decision" != "$decision_id" ]]; then
        count=$((count+1))
        jq --arg fp "$fingerprint" --arg lineage "$lineage" --arg decisionId "$decision_id" --argjson count "$count" \
          '. + {schemaVersion:1,contextFingerprint:$fp,stateLineage:$lineage,assistedDisagreementCount:$count,lastDecisionId:$decisionId,updatedAt:(now|floor)}' \
          <<<"$cadence" | cfip_atomic_write "$CFIP_RILL_HOLDOUT_STATE_FILE" || return 1
    fi
    (( count % interval == 0 ))
}

cfip_rill_holdout() (
    local decision="$1" native_json="$2" actual_outcome="$3" domains="$4" timeout_s="$5" output="$6"
    local native family candidate domain probe probes='[]' all_ok=true reward_json actual_reward native_reward epsilon holdout_timeout holdout_deadline budget_unavailable=false probe_unavailable=false error_class expected_domains=0
    cfip_rill_holdout_due "$decision" || return 2
    native="$(jq -r '.nativeOrder[0] // empty' "$decision")"; [[ -n "$native" ]] || return 2
    epsilon="${CFIP_RILL_REWARD_TIE_EPSILON:-0.02}"
    candidate="$(jq -c --arg ip "$native" '.[]|select((.ip|tostring)==$ip)' "$native_json" | head -n1)"; [[ -n "$candidate" ]] || return 2
    family="$(jq -r '.family // "ipv4"' <<<"$candidate")"
    holdout_timeout="${CFIP_RILL_HOLDOUT_TIMEOUT:-$timeout_s}"
    [[ "$holdout_timeout" =~ ^[1-9][0-9]*$ ]] || holdout_timeout="$timeout_s"
    [[ "$holdout_timeout" =~ ^[1-9][0-9]*$ ]] || return 2
    holdout_deadline=$(( $(cfip_monotonic_seconds 2>/dev/null || date +%s) + holdout_timeout ))
    CFIP_MEASUREMENT_DEADLINE="$holdout_deadline"
    IFS=',' read -r -a domain_list <<<"$domains"; expected_domains=0; for domain in "${domain_list[@]}"; do [[ -n "$domain" ]] && expected_domains=$((expected_domains+1)); done
    for domain in "${domain_list[@]}"; do
        [[ -n "$domain" ]] || continue
        probe="$(cfip_probe_one "$native" "$domain" "$family" "$holdout_timeout")" || { probe_unavailable=true; continue; }
        error_class="$(jq -r '.errorClass // empty' <<<"$probe" 2>/dev/null || printf '')"
        if [[ "$error_class" == measurement_budget || "$error_class" == evaluation_budget_exhausted ]]; then
            budget_unavailable=true
            break
        fi
        probes="$(jq -cn --argjson a "$probes" --argjson p "$probe" --argjson loss "$(jq -r '.lossRate // 1' <<<"$candidate")" --argjson throughput "$(jq -r '.downloadMBps // 0' <<<"$candidate")" '$a+[$p+{lossRate:$loss,downloadMBps:$throughput}]')"
        [[ "$(jq -r '.success' <<<"$probe")" == true ]] || all_ok=false
    done
    if [[ "$budget_unavailable" == true ]]; then
        jq -cn '{performed:false,reason:"budget_unavailable",feedbackEligible:false,holdoutFailure:false,comparison:"unavailable"}' | cfip_atomic_write "$output"
        return $?
    fi
    [[ "$(jq 'length' <<<"$probes")" == "$expected_domains" && "$expected_domains" -gt 0 ]] || {
        jq -cn --arg reason "$(if [[ "$probe_unavailable" == true ]]; then printf probe_unavailable; else printf no_complete_probe; fi)" '{performed:false,reason:$reason,feedbackEligible:false,holdoutFailure:false,comparison:"unavailable"}' | cfip_atomic_write "$output"
        return $?
    }
    local tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-holdout.XXXXXX")" || return 1
    jq -cn --arg runId "${CFIP_RUN_ID:-holdout}" --arg ip "$native" --arg decisionId "$(jq -r '.decisionId // empty' "$decision")" --argjson ok "$all_ok" --argjson probes "$probes" \
      '{schemaVersion:2,runId:$runId,decisionId:$decisionId,validated:$ok,candidateOutcome:(if $ok then "success" else "failure" end),hostOutcome:"success",censored:false,observedIp:$ip,decisionActionId:$ip,probes:$probes,holdout:true}' >"$tmp"
    reward_json="$(cfip_rill_reward_json "$tmp")"; actual_reward="$(jq -r '.reward // null' "$actual_outcome" 2>/dev/null || printf null)"; native_reward="$(jq -r '.reward // null' <<<"$reward_json")"
    jq -cn --arg native "$native" --argjson performed true --argjson success "$all_ok" --argjson actual "$actual_reward" --argjson holdout "$native_reward" --argjson epsilon "$epsilon" --argjson delta "$(jq -cn --argjson a "$actual_reward" --argjson n "$native_reward" 'if ($a|type)=="number" and ($n|type)=="number" then $a-$n else null end')" \
      '{performed:$performed,evaluationSource:"holdout",nativeTop1:$native,actualCandidateReward:$actual,nativeHoldoutReward:$holdout,rewardDelta:$delta,comparison:(if ($delta|type)!="number" then "unavailable" elif $delta>$epsilon then "win" elif $delta < (-$epsilon) then "loss" else "tie" end),failure:($success|not),holdoutFailure:($success|not),feedbackEligible:false}' | cfip_atomic_write "$output"
    rm -f "$tmp"
)

cfip_rill_record_evaluation() {
    local decision="$1" outcome="$2" holdout="${3:-}" current evaluation_window effective source native_reward rill_reward delta result fingerprint lineage decision_id holdout_performed epsilon
    [[ -s "$decision" && -s "$outcome" ]] || return 1
    [[ -n "$holdout" ]] || holdout='{}'
    [[ -f "$holdout" ]] && holdout="$(cat "$holdout")"
    current="$(cfip_rill_qualification_json)"
    evaluation_window="$(jq -c '.evaluationWindow // []' <<<"$current")"
    epsilon="${CFIP_RILL_REWARD_TIE_EPSILON:-0.02}"
    effective="$(jq -r '.effectiveMode // "off"' "$decision")"
    holdout_performed="$(jq -r '.performed // false' <<<"$holdout" 2>/dev/null || printf false)"
    source=""
    native_reward=null; rill_reward=null; delta=null; result=unavailable
    if [[ "$effective" == assisted && "$holdout_performed" == true ]]; then
        source=holdout
        native_reward="$(jq -r '.nativeHoldoutReward // null' <<<"$holdout")"
        rill_reward="$(jq -r '.actualCandidateReward // null' <<<"$holdout")"
        delta="$(jq -r '.rewardDelta // null' <<<"$holdout")"
        result="$(jq -r '.comparison // "unavailable"' <<<"$holdout")"
    elif [[ "$effective" == shadow && "$(jq -r '.disagreement // false' "$outcome")" == true ]]; then
        source=shadow
        native_reward="$(jq -r '.nativeCounterfactualReward // null' "$outcome")"
        rill_reward="$(jq -r '.rillShadowReward // .reward // null' "$outcome")"
        delta="$(jq -r '.rewardDelta // null' "$outcome")"
        result="$(jq -r --argjson epsilon "$epsilon" '.comparison // (if (.rewardDelta|type)!="number" then "unavailable" elif .rewardDelta>$epsilon then "win" elif .rewardDelta < (-$epsilon) then "loss" else "tie" end)' "$outcome")"
    else
        return 0
    fi
    [[ "$native_reward" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || native_reward=null
    [[ "$rill_reward" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || rill_reward=null
    [[ "$delta" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || delta=null
    [[ "$result" == win || "$result" == tie || "$result" == loss ]] || result=unavailable
    fingerprint="$(cfip_rill_context_fingerprint 2>/dev/null || printf '')"; lineage="$(cfip_rill_lineage_id 2>/dev/null || printf '')"; decision_id="$(jq -r '.decisionId // empty' "$decision")"
    evaluation_window="$(jq -cn --argjson w "$(jq -c '.evaluationWindow // []' <<<"$current")" --arg source "$source" --arg fp "$fingerprint" --arg lineage "$lineage" --arg decisionId "$decision_id" --argjson native "$native_reward" --argjson rill "$rill_reward" --argjson delta "$delta" --arg result "$result" --argjson holdout "$holdout_performed" --argjson at "$(cfip_rill_now_seconds)" '($w + [{evaluationSource:$source,contextFingerprint:$fp,stateLineage:$lineage,decisionId:$decisionId,nativeReward:$native,rillReward:$rill,rewardDelta:$delta,comparisonResult:$result,holdoutPerformed:$holdout,feedbackEligible:false,at:$at}])[-64:]')"
    jq --argjson evaluation "$evaluation_window" '. + {evaluationWindow:$evaluation,legacyEvaluationCompatibility:false}' <<<"$current" | cfip_atomic_write "$CFIP_RILL_QUALIFICATION_FILE" || return 1
    cfip_rill_record_qualification "" false false false
}

cfip_rill_record_evidence() {
    local decision="$1" outcome="$2" holdout="${3:-}" current actual native rill delta result qualification context fp lineage effective requested authority agreement native_top1 holdout_performed holdout_reward feedback_eligible evidence epsilon confidence_level confidence_reasons evaluation_source
    [[ -f "$holdout" ]] && holdout="$(cat "$holdout" 2>/dev/null || printf '{}')"
    [[ -s "$decision" && -s "$outcome" ]] || return 1
    [[ -n "$holdout" ]] || holdout='{}'
    [[ -f "$holdout" ]] && holdout="$(cat "$holdout")"
    current="$(cfip_rill_evidence_json)"; context="$(cfip_rill_context_json)"; fp="$(cfip_rill_context_fingerprint)"
    actual="$(jq -r '.reward // null' "$outcome" 2>/dev/null || printf null)"
    native="$(jq -r '.nativeCounterfactualReward // null' "$outcome" 2>/dev/null || printf null)"
    rill="$(jq -r '.rillShadowReward // .reward // null' "$outcome" 2>/dev/null || printf null)"
    delta="$(jq -r '.rewardDelta // null' "$outcome" 2>/dev/null || printf null)"
    epsilon="${CFIP_RILL_REWARD_TIE_EPSILON:-0.02}"
    result="$(jq -r --argjson epsilon "$epsilon" '.comparison // (if (.rewardDelta|type)!="number" then "unavailable" elif .rewardDelta>$epsilon then "win" elif .rewardDelta < (-$epsilon) then "loss" else "tie" end)' "$outcome" 2>/dev/null || printf unavailable)"
    requested="$(jq -r '.requestedMode // "off"' "$decision")"; effective="$(jq -r '.effectiveMode // "off"' "$decision")"; authority="$(jq -r '.authorityActionId // empty' "$decision")"; native_top1="$(jq -r '.nativeOrder[0] // empty' "$decision")"; agreement="$(jq -r '.nativeRillTop1Agreement // false' "$decision")"; qualification="$(cfip_rill_qualification_json | jq -r '.state // "cold"')"; lineage="$(cfip_rill_lineage_id 2>/dev/null || printf '')"
    holdout_performed="$(jq -r '.performed // false' <<<"$holdout" 2>/dev/null || printf false)"; holdout_reward="$(jq -r '.nativeHoldoutReward // null' <<<"$holdout" 2>/dev/null || printf null)"; feedback_eligible="$(jq -r 'if has("feedbackEligible") then .feedbackEligible else empty end' "$outcome" 2>/dev/null || true)"; if [[ -z "$feedback_eligible" ]]; then feedback_eligible="$(jq -r 'if has("feedbackEligible") then .feedbackEligible else true end' <<<"$holdout" 2>/dev/null || printf true)"; fi; [[ "$feedback_eligible" == true ]] || feedback_eligible=false
    if [[ "$effective" == assisted ]]; then
        native="$holdout_reward"
        delta="$(jq -cn --argjson a "$actual" --argjson n "$native" 'if ($a|type)=="number" and ($n|type)=="number" then $a-$n else null end')"
        result="$(jq -rn --argjson d "$delta" --argjson epsilon "$epsilon" 'if ($d|type)!="number" then "unavailable" elif $d>$epsilon then "win" elif $d < (-$epsilon) then "loss" else "tie" end')"
    fi
    confidence_level="$(jq -r '.confidenceLevel // "low"' "$decision" 2>/dev/null || printf low)"; confidence_reasons="$(jq -c '.confidenceReasons // []' "$decision" 2>/dev/null || printf '[]')"
    evaluation_source=null; [[ "$effective" == assisted && "$holdout_performed" == true ]] && evaluation_source=holdout; [[ "$effective" == shadow && "$result" != unavailable ]] && evaluation_source=shadow
    evidence="$(jq -cn --arg runId "${CFIP_RUN_ID:-}" --argjson at "$(date +%s)" --arg fp "$fp" --arg lineage "$lineage" --argjson context "$context" --arg requested "$requested" --arg effective "$effective" --arg nativeTop1 "$native_top1" --arg rillTop1 "$(jq -r '.rillOrder[0] // .rillSelectedActionId // empty' "$decision")" --arg authority "$authority" --argjson agreement "$agreement" --argjson holdout "$holdout" --argjson actual "$actual" --argjson native "$native" --argjson rill "$rill" --argjson delta "$delta" --arg result "$result" --argjson stateGeneration "$(jq -r '.generation // 0' "$decision")" --arg qualification "$qualification" --argjson holdoutPerformed "$holdout_performed" --argjson holdoutReward "$holdout_reward" --argjson feedbackEligible "$feedback_eligible" --arg confidenceLevel "$confidence_level" --argjson confidenceReasons "$confidence_reasons" --arg evaluationSource "$evaluation_source" \
      '{runId:$runId,at:$at,contextSchemaVersion:1,contextFingerprint:$fp,stateLineage:$lineage,contextSummary:$context,requestedMode:$requested,effectiveMode:$effective,nativeTop1:$nativeTop1,rillTop1:$rillTop1,authorityActionId:$authority,nativeRillTop1Agreement:$agreement,evaluationSource:(if $evaluationSource=="null" then null else $evaluationSource end),holdoutPerformed:$holdoutPerformed,actualReward:$actual,nativeCounterfactualReward:(if ($native|type)=="number" then $native else (if ($holdoutReward|type)=="number" then $holdoutReward else null end) end),rewardDelta:$delta,comparisonResult:$result,holdoutFailure:($holdout.failure//false),feedbackEligible:$feedbackEligible,stateGeneration:$stateGeneration,modelGeneration:2,qualificationState:$qualification,confidenceLevel:$confidenceLevel,confidenceReasons:$confidenceReasons,holdout:$holdout}' )"
    jq --argjson item "$evidence" --argjson limit "$CFIP_RILL_EVIDENCE_LIMIT" '(. + [$item])[-$limit:]' <<<"$current" >"$CFIP_RILL_EVIDENCE_FILE.tmp" || return 1
    cfip_rill_write_evidence "$CFIP_RILL_EVIDENCE_FILE.tmp" || { rm -f "$CFIP_RILL_EVIDENCE_FILE.tmp"; return 1; }
    rm -f "$CFIP_RILL_EVIDENCE_FILE.tmp"
    cfip_rill_record_evaluation "$decision" "$outcome" "$holdout" || return 1
    current="$(cfip_rill_qualification_json)"
    jq --arg level "$confidence_level" --argjson reasons "$confidence_reasons" '. + {lastDecisionConfidenceLevel:$level,lastDecisionConfidenceReasons:$reasons}' <<<"$current" | cfip_atomic_write "$CFIP_RILL_QUALIFICATION_FILE"
}

cfip_rill_evidence_aggregate_json() {
    local context fingerprint context_changed_at lineage
    context="$(cfip_rill_context_json 2>/dev/null || printf '{}')"
    fingerprint="$(cfip_rill_context_fingerprint 2>/dev/null || printf '')"
    lineage="$(cfip_rill_lineage_id 2>/dev/null || printf '')"
    context_changed_at=null
    if [[ -s "$CFIP_RILL_STATE_META_FILE" ]]; then
        context_changed_at="$(jq -c '.contextChangedAt // null' "$CFIP_RILL_STATE_META_FILE" 2>/dev/null || printf null)"
    fi
    cfip_rill_evidence_json | jq --arg fp "$fingerprint" --arg lineage "$lineage" --argjson context "$context" --argjson changedAt "$context_changed_at" '
      def comparable: select(.comparisonResult=="win" or .comparisonResult=="tie" or .comparisonResult=="loss");
      . as $all | [$all[]|select(.contextFingerprint==$fp and (.stateLineage==$lineage or .stateLineage==null))] as $current | [$current[]|comparable] as $c |
      {comparableDecisions:($c|length),wins:([$c[]|select(.comparisonResult=="win")]|length),ties:([$c[]|select(.comparisonResult=="tie")]|length),losses:([$c[]|select(.comparisonResult=="loss")]|length),winRate:(if ($c|length)>0 then ([$c[]|select(.comparisonResult=="win")]|length)/($c|length) else null end),meanRewardDelta:([$c[]|select(.rewardDelta|type=="number")|.rewardDelta]|if length>0 then add/length else null end),medianRewardDelta:([$c[]|select(.rewardDelta|type=="number")|.rewardDelta]|if length>0 then sort|.[(length-1)/2|floor] else null end),severeRegressionCount:([$c[]|select((.rewardDelta|type=="number") and .rewardDelta < -0.25)]|length),assistedSelections:([$current[]|select(.effectiveMode=="assisted")]|length),holdoutCount:([$current[]|select(.holdoutPerformed==true)]|length),holdoutFailures:([$current[]|select(.holdoutFailure==true)]|length),currentContextFingerprint:(if $fp!="" then $fp else ($current[-1].contextFingerprint // null) end),currentLineageId:(if $lineage!="" then $lineage else null end),contextSummary:$context,contextChangedAt:$changedAt}'
}

cfip_rill_feedback() (
    local decision_json="$1" outcome_json="$2" request response_file rc=0 decision_id selected_id observed_id schema state_generation expected_request_id reward candidate_outcome host_outcome delayed partition
    [[ "${CFIP_RILL_ENABLED:-false}" == true && -x "$CFIP_RILL_RUNTIME" ]] || return 0
    partition="$(jq -r '.partitionKey // empty' "$decision_json" 2>/dev/null || true)"
    [[ -z "$partition" || "$partition" == "$CFIP_RILL_CANDIDATE_PARTITION_KEY" ]] || { cfip_log "Rill feedback rejected: non-candidate partition"; return 12; }
    CFIP_RILL_PARTITION_KEY="$CFIP_RILL_CANDIDATE_PARTITION_KEY"
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
    rm -f "$response_file"; cfip_rill_mark_selected "$selected_id"; delayed="${CFIP_RILL_PROCESSING_DELAYED:-false}"; cfip_rill_record_qualification "$candidate_outcome" true "$delayed" false "$reward" "$outcome_json"; return 0
)

cfip_rill_queue_feedback() {
    local decision="$1" outcome="$2" domains="${3:-}" queued="$(date +%s)" due="$(($(date +%s)+${CFIP_RILL_DELAYED_FEEDBACK_SECONDS:-600}))" expires="$(($(date +%s)+${CFIP_RILL_DELAYED_FEEDBACK_EXPIRY_SECONDS:-86400}))" current schema lineage partition context context_fp
    if [[ "$(jq -r '.feedbackEligible // true' "$outcome" 2>/dev/null || printf true)" != true ]]; then
        cfip_log "Rill feedback suppressed: outcome is not feedback-eligible"
        return 0
    fi
    schema="$(cfip_rill_schema_hash 2>/dev/null || printf '')"; lineage="$(cfip_rill_lineage_id 2>/dev/null || printf '')"
    partition="$CFIP_RILL_CANDIDATE_PARTITION_KEY"
    current='[]'
    if [[ -s "$CFIP_RILL_PENDING_FILE" ]] && jq -e 'type=="array"' "$CFIP_RILL_PENDING_FILE" >/dev/null 2>&1; then
        current="$(cat "$CFIP_RILL_PENDING_FILE")"
    fi
    context="$(cfip_rill_context_json)"; context_fp="$(cfip_rill_context_fingerprint)"
    jq -cn --argjson current "$current" --argjson due "$due" --argjson expires "$expires" --argjson queued "$queued" --arg schema "$schema" --arg lineage "$lineage" --arg partition "$partition" --arg domains "$domains" --arg contextFp "$context_fp" --argjson context "$context" --argjson decision "$(cat "$decision")" --argjson outcome "$(cat "$outcome")" \
      '($current + [{dueAt:$due,expiresAt:$expires,decision:$decision,outcome:$outcome,domains:(if $domains=="" then null else $domains end),queuedAt:$queued,modelGeneration:2,featureSchemaHash:$schema,contextSchemaVersion:1,contextFingerprint:$contextFp,contextSummary:$context,partitionKey:$partition,stateGeneration:($decision.generation//0),stateLineage:(if $lineage=="" then null else $lineage end)}] | reverse | unique_by(.decision.decisionId // ((.decision.selectedActionId // "") + ":" + ((.stateGeneration // 0)|tostring))) | reverse)[-64:]' | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"
}

cfip_rill_record_delayed_counter() {
    local field="$1" current
    current="$(cfip_rill_qualification_json)"
    jq --arg field "$field" '(.[$field] //= 0) | .[$field] += 1 | .updatedAt=(now|floor)' <<<"$current" | cfip_atomic_write "$CFIP_RILL_QUALIFICATION_FILE"
}

cfip_rill_refresh_delayed_observation() {
    local decision="$1" original="$2" domains="$3" output="$4" selected family domain probe probes='[]' all_ok=true candidate loss throughput reward_json tmp
    selected="$(jq -r '.observedIp // .decisionActionId // empty' "$original")"; [[ -n "$selected" ]] || return 1
    family="$(jq -r '.probes[0].family // empty' "$original")"; [[ -n "$family" ]] || family="$(cfip_ip_family "$selected" 2>/dev/null || printf ipv4)"
    candidate="$(jq -c --arg ip "$selected" '.candidates[]? | select((.ip|tostring)==$ip)' "$decision" 2>/dev/null | head -n1)"
    [[ -n "$candidate" ]] || candidate='{}'
    loss="$(jq -r '.lossRate // 1' <<<"$candidate")"; throughput="$(jq -r '.downloadMBps // 0' <<<"$candidate")"
    IFS=',' read -r -a domain_list <<<"$domains"
    for domain in "${domain_list[@]}"; do
        [[ -n "$domain" ]] || continue
        probe="$(cfip_probe_one "$selected" "$domain" "$family" "${CFIP_RILL_DELAYED_PROBE_TIMEOUT:-5}")" || return 1
        probes="$(jq -cn --argjson a "$probes" --argjson p "$probe" --argjson loss "$loss" --argjson throughput "$throughput" '$a+[$p+{lossRate:$loss,downloadMBps:$throughput}]')"
        [[ "$(jq -r '.success' <<<"$probe")" == true ]] || all_ok=false
    done
    [[ "$(jq 'length' <<<"$probes")" -gt 0 ]] || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-delayed-outcome.XXXXXX")" || return 1
    jq -cn --arg runId "${CFIP_RUN_ID:-delayed}" --arg ip "$selected" --arg decisionId "$(jq -r '.decisionId // empty' "$decision")" --argjson ok "$all_ok" --argjson probes "$probes" '{schemaVersion:2,runId:$runId,decisionId:$decisionId,validated:$ok,candidateOutcome:(if $ok then "success" else "failure" end),hostOutcome:"success",censored:false,observedIp:$ip,decisionActionId:$ip,probes:$probes,delayedObservation:true}' >"$tmp"
    reward_json="$(cfip_rill_reward_json "$tmp")"
    jq --argjson reward "$reward_json" --argjson original "$(cat "$original")" '. + {reward:$reward.reward,rewardVersion:$reward.rewardVersion,rewardComponents:$reward.components,worstDomain:$reward.worstDomain,nativeCounterfactualReward:($original.nativeCounterfactualReward//null),rillShadowReward:$reward.reward,rewardDelta:(if ($original.nativeCounterfactualReward|type)=="number" then $reward.reward-$original.nativeCounterfactualReward else null end),disagreement:($original.disagreement//false)}' "$tmp" | cfip_atomic_write "$output"
    rm -f "$tmp"
}

cfip_rill_process_pending_feedback() {
    [[ -s "$CFIP_RILL_PENDING_FILE" ]] || return 0
    if ! jq -e 'type=="array" and length<=64 and all(.[]; (.decision|type)=="object" and (.outcome|type)=="object" and ((.dueAt|type)=="number") and ((.expiresAt//0|type)=="number"))' "$CFIP_RILL_PENDING_FILE" >/dev/null 2>&1; then
        cfip_rill_quarantine_pending_queue || return 1
        return 0
    fi
    local now current due expires item tmp_decision tmp_outcome refreshed_outcome feedback_rc remaining='[]' domains current_lineage item_lineage item_generation item_partition item_context current_context_fp
    now="$(date +%s)"
    current="$(cat "$CFIP_RILL_PENDING_FILE" 2>/dev/null || printf '[]')"
    current_lineage="$(cfip_rill_lineage_id 2>/dev/null || printf '')"
    current_context_fp="$(cfip_rill_context_fingerprint 2>/dev/null || printf '')"
    while IFS= read -r item; do
        due="$(jq -r '.dueAt // 0' <<<"$item")"
        if ((due > now)); then remaining="$(jq -cn --argjson a "$remaining" --argjson i "$item" '$a+[$i]')"; continue; fi
        expires="$(jq -r '.expiresAt // 0' <<<"$item")"
        if ((expires > 0 && expires <= now)); then
            cfip_rill_record_delayed_counter delayedExpired
            continue
        fi
        if [[ "$(jq -r '.rejectedReason // empty' <<<"$item")" == context_changed ]]; then
            cfip_rill_record_delayed_counter delayedRejected
            cfip_log "Rill delayed feedback rejected: context_changed"
            continue
        fi
        item_partition="$(jq -r '.partitionKey // .decision.partitionKey // empty' <<<"$item")"
        if [[ "$item_partition" != "$CFIP_RILL_CANDIDATE_PARTITION_KEY" ]]; then
            cfip_rill_record_delayed_counter delayedRejected
            cfip_log "Rill delayed feedback rejected: invalid_partition"
            continue
        fi
        item_context="$(jq -r '.contextFingerprint // empty' <<<"$item")"
        if [[ -n "$item_context" && "$item_context" != "$current_context_fp" ]]; then
            cfip_rill_record_delayed_counter delayedRejected
            cfip_log "Rill delayed feedback rejected: context_changed"
            continue
        fi
        CFIP_RILL_PARTITION_KEY="$CFIP_RILL_CANDIDATE_PARTITION_KEY"
        item_lineage="$(jq -r '.stateLineage // empty' <<<"$item")"; item_generation="$(jq -r '.stateGeneration // 0' <<<"$item")"
        if [[ "$(jq -r '.modelGeneration // 0' <<<"$item")" != "$CFIP_RILL_MODEL_GENERATION" || "$(jq -r '.featureSchemaHash // empty' <<<"$item")" != "$(cfip_rill_schema_hash 2>/dev/null || printf '')" ]]; then
            cfip_rill_record_delayed_counter delayedRejected
            cfip_log "Rill delayed feedback rejected: generation_or_schema_mismatch"
            continue
        fi
        if [[ -n "$item_lineage" && "$item_lineage" != "$current_lineage" ]]; then
            cfip_rill_record_delayed_counter delayedRejected
            cfip_log "Rill delayed feedback rejected: lineage_mismatch"
            continue
        fi
        if [[ -f "${CFIP_RILL_STATE:-}" ]] && ((item_generation > 0 && $(cfip_rill_state_generation) < item_generation)); then
            cfip_rill_record_delayed_counter delayedRejected
            cfip_log "Rill delayed feedback rejected: state_generation_mismatch"
            continue
        fi
        tmp_decision="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-pending-decision.XXXXXX")"; tmp_outcome="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-pending-outcome.XXXXXX")"
        jq -c '.decision' <<<"$item" >"$tmp_decision"; jq -c '.outcome' <<<"$item" >"$tmp_outcome"
        domains="$(jq -r '.domains // empty' <<<"$item")"
        if [[ -n "$domains" ]]; then
            refreshed_outcome="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-refreshed-outcome.XXXXXX")"
            if cfip_rill_refresh_delayed_observation "$tmp_decision" "$tmp_outcome" "$domains" "$refreshed_outcome"; then mv "$refreshed_outcome" "$tmp_outcome"; else rm -f "$refreshed_outcome"; fi
        fi
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
    response="$(cfip_rill_runtime_call "$request" 2>/dev/null || true)"
    if jq -e '.response.kind=="inspection" and (.response.summary|type)=="object"' <<<"$response" >/dev/null 2>&1; then jq -c '.response.summary' <<<"$response"; else printf '{}'; fi
}
