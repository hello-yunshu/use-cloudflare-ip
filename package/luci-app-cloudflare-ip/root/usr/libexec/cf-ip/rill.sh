#!/usr/bin/env bash
# shellcheck shell=bash

# Consumer mapping only. The optional package owns this file; the generic
# runtime remains an independently packaged dependency.
CFIP_RILL_SCHEMA_FILE="${CFIP_RILL_SCHEMA_FILE:-/usr/share/cf-ip/rill-feature-schema-v1.json}"

cfip_rill_schema_hash() {
    [[ -s "$CFIP_RILL_SCHEMA_FILE" ]] || return 1
    sha256sum "$CFIP_RILL_SCHEMA_FILE" | awk '{print $1}'
}

cfip_rill_state_generation() {
    [[ -f "$CFIP_RILL_STATE" ]] || { printf '0'; return 0; }
    jq -r '.handlerSnapshot.stateGeneration // 0' "$CFIP_RILL_STATE" 2>/dev/null || printf '0'
}

cfip_rill_runtime_call() {
    local request="$1" response schema
    [[ -x "$CFIP_RILL_RUNTIME" ]] || return 3
    schema="$(cfip_rill_schema_hash)" || return 4
    mkdir -p "${CFIP_RILL_STATE%/*}"
    response="$(printf '%s\n' "$request" | "$CFIP_RILL_RUNTIME" preview-serve --state "$CFIP_RILL_STATE" --feature-schema-hash "$schema" --model-generation 1 2>>"$CFIP_LOG_FILE")" || return 5
    [[ -n "$response" ]] || return 6
    printf '%s' "$response"
}

cfip_rill_status_json() {
    local request response schema
    schema="$(cfip_rill_schema_hash 2>/dev/null || true)"
    [[ -n "$schema" ]] || { jq -cn --arg mode "$CFIP_RILL_MODE" '{available:false,state:"schema-unavailable",mode:$mode}'; return 0; }
    request="$(jq -cn --arg id "status-$CFIP_RUN_ID" --arg schema "$schema" '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},featureSchemaHash:$schema,modelGeneration:1,stateGeneration:0,payloadLimit:1048576,request:{method:"handshake"}}')"
    response="$(cfip_rill_runtime_call "$request" 2>/dev/null || true)"
    if jq -e --arg schema "$schema" '.response.kind=="handshake" and .apiVersion==3 and (.response.capabilities|type=="array") and .response.featureSchemaHash==$schema and (.response.capabilities|index("org.rill.preview.decide")) and (.response.capabilities|index("org.rill.preview.feedback")) and .response.handlerApiVersion==2' <<<"$response" >/dev/null 2>&1; then
        jq -cn --arg mode "$CFIP_RILL_MODE" --argjson s "$response" '{available:true,state:"healthy",mode:$mode,runtimeVersion:$s.runtimeIdentity.version,runtimeApiVersion:$s.apiVersion,capabilities:$s.response.capabilities,featureSchemaHash:$s.response.featureSchemaHash,handlerApiVersion:$s.response.handlerApiVersion}'
    else
        jq -cn --arg mode "$CFIP_RILL_MODE" '{available:false,state:"incompatible",runtimeVersion:"",runtimeApiVersion:3,mode:$mode}'
    fi
}

cfip_rill_actions_json() {
    jq -c '[.[] | {id:(.ip|tostring),features:[(.avgLatencyMs//0),(.downloadMBps//0),(.lossRate//0),(.connectMs//0),(.tlsMs//0),(.ttfbMs//0),(.totalMs//0),(.nativeRank//0)]}]' "$1"
}

cfip_rill_rank_shadow() {
    local native_json="$1" output="$2" request tmp rc=0 response_bytes native_set rill_set schema actions selected_id generation
    [[ "$CFIP_RILL_ENABLED" == true && "$CFIP_RILL_MODE" != off ]] || return 2
    [[ -x "$CFIP_RILL_RUNTIME" ]] || return 3
    schema="$(cfip_rill_schema_hash)" || return 4
    actions="$(cfip_rill_actions_json "$native_json")" || return 4
    request="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-request.XXXXXX")" || return 4
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-response.XXXXXX")" || { rm -f "$request"; return 4; }
    jq -cn --arg id "decision-$CFIP_RUN_ID" --arg schema "$schema" --argjson generation "$(cfip_rill_state_generation)" --argjson actions "$actions" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},capability:"org.rill.preview.decide",featureSchemaHash:$schema,modelGeneration:1,stateGeneration:$generation,payloadLimit:1048576,request:{method:"decide",context:{actions:$actions}}}' >"$request"
    if command -v timeout >/dev/null 2>&1; then
        timeout "${CFIP_RILL_TIMEOUT_S}s" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation 1' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$schema" >"$tmp" 2>>"$CFIP_LOG_FILE" || rc=$?
    else
        cfip_run_with_timeout "$CFIP_RILL_TIMEOUT_S" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation 1' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$schema" >"$tmp" 2>>"$CFIP_LOG_FILE" || rc=$?
    fi
    rm -f "$request"
    response_bytes="$(wc -c <"$tmp" 2>/dev/null || printf 0)"
    if ((rc != 0 || response_bytes > 262144)) || ! jq -e '.response.kind=="result" and .response.output.accepted==true and (.response.output.selectedActionId|type=="string") and ((.response.output.selectedActionId|length)>0) and ((.response.output.selectedActionId|length)<=96) and (.response.output.scores|type=="array") and ((.response.output.scores|length)>0) and all(.response.output.scores[]; (.id|type)=="string" and (.score|type)=="number")' "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"; return 5
    fi
    selected_id="$(jq -r '.response.output.selectedActionId' "$tmp")"
    native_set="$(jq -c '[.[].ip|tostring]|sort' "$native_json")"
    rill_set="$(jq -c '[.response.output.scores[].id]|sort' "$tmp")"
    [[ "$native_set" == "$rill_set" ]] || { rm -f "$tmp"; return 6; }
    if ! jq -e --arg id "$selected_id" 'any(.[]; (.ip|tostring)==$id)' "$native_json" >/dev/null; then
        rm -f "$tmp"; return 7
    fi
    generation="$(jq -r '.stateGeneration' "$tmp")"
    jq --arg selected "$selected_id" --arg generation "$generation" --argjson candidates "$(cat "$native_json")" \
      '{success:true,decisionId:.requestId,selectedActionId:$selected,generation:($generation|tonumber),candidates:($candidates|sort_by(if (.ip|tostring)==$selected then 0 else 1 end)),runtimeApiVersion:.apiVersion,shadowCandidateInvariant:true}' "$tmp" >"$output"
    rm -f "$tmp"
}

cfip_rill_feedback() {
    local decision_json="$1" outcome_json="$2" request rc=0 generation selected_id schema
    [[ "$CFIP_RILL_ENABLED" == true && -x "$CFIP_RILL_RUNTIME" ]] || return 0
    [[ "$(jq -r '.validated//false' "$outcome_json")" == true ]] || return 0
    generation="$(jq '.generation // null' "$decision_json")"; [[ "$generation" != null ]] || return 0
    local decision_id; decision_id="$(jq -r '.decisionId // empty' "$decision_json")"; [[ -n "$decision_id" ]] || return 0
    selected_id="$(jq -r '.selectedActionId // empty' "$decision_json")"; [[ -n "$selected_id" ]] || return 0
    schema="$(cfip_rill_schema_hash)" || return 1
    request="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-feedback.XXXXXX")" || return 1
    jq -cn --arg id "feedback-$CFIP_RUN_ID" --arg decisionId "$decision_id" --arg selected "$selected_id" --arg schema "$schema" --argjson stateGeneration "$(cfip_rill_state_generation)" --argjson reward "$(jq -r '.reward // 0' "$outcome_json")" --argjson outcomeGeneration "$generation" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},capability:"org.rill.preview.feedback",featureSchemaHash:$schema,modelGeneration:1,stateGeneration:$stateGeneration,payloadLimit:1048576,request:{method:"feedback",decisionId:$decisionId,selectedActionId:$selected,reward:$reward,outcomeTimeMs:(now*1000|floor),generation:1}}' >"$request"
    if command -v timeout >/dev/null 2>&1; then
        timeout "${CFIP_RILL_TIMEOUT_S}s" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation 1' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$schema" >/dev/null 2>>"$CFIP_LOG_FILE" || rc=$?
    else
        cfip_run_with_timeout "$CFIP_RILL_TIMEOUT_S" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation 1' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$schema" >/dev/null 2>>"$CFIP_LOG_FILE" || rc=$?
    fi
    rm -f "$request"; return "$rc"
}
