#!/usr/bin/env bash
# shellcheck shell=bash

# Cloudflare is a consumer of the generic Rill Runtime.  This file only maps
# Cloudflare's candidate/outcome data to the generic IPC v3 action contract;
# it never downloads, installs, removes, or owns a Rill executable.
CFIP_RILL_FEATURE_SCHEMA_HASH=abababababababababababababababababababababababababababababababab

cfip_rill_state_generation() {
    [[ -f "$CFIP_RILL_STATE" ]] || { printf '0'; return 0; }
    jq -r '.handlerSnapshot.stateGeneration // 0' "$CFIP_RILL_STATE" 2>/dev/null || printf '0'
}

cfip_rill_runtime_call() {
    local request="$1" response
    [[ -x "$CFIP_RILL_RUNTIME" ]] || return 3
    mkdir -p "${CFIP_RILL_STATE%/*}"
    response="$(printf '%s\n' "$request" | "$CFIP_RILL_RUNTIME" preview-serve --state "$CFIP_RILL_STATE" --feature-schema-hash "$CFIP_RILL_FEATURE_SCHEMA_HASH" --model-generation 1 2>>"$CFIP_LOG_FILE")" || return 4
    [[ -n "$response" ]] || return 5
    printf '%s' "$response"
}

cfip_rill_status_json() {
    local request response
    request="$(jq -cn --arg id "status-$CFIP_RUN_ID" '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},modelGeneration:1,stateGeneration:0,payloadLimit:1048576,request:{method:"handshake"}}')"
    response="$(cfip_rill_runtime_call "$request" 2>/dev/null || true)"
    if jq -e '.response.kind=="handshake" and .apiVersion==3 and (.response.capabilities|type=="array")' <<<"$response" >/dev/null 2>&1; then
        jq -cn --arg mode "$CFIP_RILL_MODE" --argjson s "$response" '{available:true,state:"healthy",mode:$mode,runtimeVersion:$s.runtimeIdentity.version,runtimeApiVersion:$s.apiVersion,capabilities:$s.response.capabilities,featureSchemaHash:$s.response.featureSchemaHash,handlerApiVersion:$s.response.handlerApiVersion}'
    else
        jq -cn --arg mode "$CFIP_RILL_MODE" '{available:false,state:"unavailable",runtimeVersion:"",runtimeApiVersion:3,mode:$mode}'
    fi
}

cfip_rill_rank_shadow() {
    local native_json="$1" output="$2" request tmp rc=0 response_bytes native_set rill_set created_at
    [[ "$CFIP_RILL_ENABLED" == true && "$CFIP_RILL_MODE" != off ]] || return 2
    [[ -x "$CFIP_RILL_RUNTIME" ]] || return 3
    request="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-request.XXXXXX")" || return 4
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-response.XXXXXX")" || { rm -f "$request"; return 4; }
    jq -cn --arg id "decision-$CFIP_RUN_ID" --argjson generation "$(cfip_rill_state_generation)" --argjson actions "$(cat "$native_json")" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},capability:"org.rill.preview.decide",featureSchemaHash:"abababababababababababababababababababababababababababababababab",modelGeneration:1,stateGeneration:$generation,payloadLimit:1048576,request:{method:"decide",context:{actions:$actions}}}' >"$request"
    if command -v timeout >/dev/null 2>&1; then
        timeout "${CFIP_RILL_TIMEOUT_S}s" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation 1' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$CFIP_RILL_FEATURE_SCHEMA_HASH" >"$tmp" 2>>"$CFIP_LOG_FILE" || rc=$?
    else
        cfip_run_with_timeout "$CFIP_RILL_TIMEOUT_S" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation 1' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$CFIP_RILL_FEATURE_SCHEMA_HASH" >"$tmp" 2>>"$CFIP_LOG_FILE" || rc=$?
    fi
    rm -f "$request"
    response_bytes="$(wc -c <"$tmp" 2>/dev/null || printf 0)"
    if ((rc != 0 || response_bytes > 262144)) || ! jq -e '.response.kind=="result" and .response.output.accepted==true and (.response.output.selectedAction|type=="number") and ((.response.output.selectedAction)>=0) and ((.response.output.selectedAction)<128)' "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"; return 5
    fi
    native_set="$(jq -c '[.[].ip]|sort' "$native_json")"; rill_set="$native_set"
    [[ "$native_set" == "$rill_set" ]] || { rm -f "$tmp"; return 6; }
    jq --argjson selected "$(jq -r '.response.output.selectedAction' "$tmp")" --argjson generation "$(jq -r '.stateGeneration' "$tmp")" --argjson candidates "$(cat "$native_json")" \
      '{success:true,decisionId:.requestId,selectedArm:$selected,generation:$generation,candidates:($candidates|to_entries|sort_by(if .key==$selected then 0 else 1 end)|map(.value)),runtimeApiVersion:.apiVersion}' "$tmp" >"$output"
}

cfip_rill_feedback() {
    local decision_json="$1" outcome_json="$2" request rc=0 generation selected_arm
    [[ "$CFIP_RILL_ENABLED" == true && -x "$CFIP_RILL_RUNTIME" ]] || return 0
    [[ "$(jq -r '.validated//false' "$outcome_json")" == true ]] || return 0
    generation="$(jq '.generation // null' "$decision_json")"; [[ "$generation" != null ]] || return 0
    local decision_id; decision_id="$(jq -r '.decisionId // empty' "$decision_json")"; [[ -n "$decision_id" ]] || return 0
    selected_arm="$(jq '.selectedArm // 0' "$decision_json")"
    [[ "$selected_arm" =~ ^[0-9]+$ ]] || return 0
    request="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-feedback.XXXXXX")" || return 1
    jq -cn --arg id "feedback-$CFIP_RUN_ID" --arg decisionId "$decision_id" --argjson generation "$(cfip_rill_state_generation)" --argjson outcomeGeneration "$generation" --argjson selectedArm "$selected_arm" --argjson reward "$(jq -r '.reward // 0' "$outcome_json")" \
      '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},capability:"org.rill.preview.feedback",featureSchemaHash:"abababababababababababababababababababababababababababababababab",modelGeneration:1,stateGeneration:$generation,payloadLimit:1048576,request:{method:"feedback",decisionId:$decisionId,selectedArm:$selectedArm,reward:$reward,outcomeTimeMs:(now*1000|floor),generation:1}}' >"$request"
    if command -v timeout >/dev/null 2>&1; then
        timeout "${CFIP_RILL_TIMEOUT_S}s" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation 1' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$CFIP_RILL_FEATURE_SCHEMA_HASH" >/dev/null 2>>"$CFIP_LOG_FILE" || rc=$?
    else
        cfip_run_with_timeout "$CFIP_RILL_TIMEOUT_S" sh -c 'cat "$1" | "$2" preview-serve --state "$3" --feature-schema-hash "$4" --model-generation 1' sh "$request" "$CFIP_RILL_RUNTIME" "$CFIP_RILL_STATE" "$CFIP_RILL_FEATURE_SCHEMA_HASH" >/dev/null 2>>"$CFIP_LOG_FILE" || rc=$?
    fi
    rm -f "$request"; return "$rc"
}
