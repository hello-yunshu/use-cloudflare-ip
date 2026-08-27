#!/usr/bin/env bash
# shellcheck shell=bash

cfip_rill_status_json() {
    local resp
    if [[ ! -x "$CFIP_RILL_ADAPTER" ]]; then
        jq -cn --arg mode "$CFIP_RILL_MODE" '{available:false,state:"unavailable",rillVersion:"",mode:$mode}'
        return 0
    fi
    resp="$("$CFIP_RILL_ADAPTER" status --state "$CFIP_RILL_STATE" 2>/dev/null || true)"
    if jq -e '.success==true and .rillVersion=="1.5.3" and .adapterProtocolVersion==1' <<<"$resp" >/dev/null 2>&1; then
        jq -cn --arg mode "$CFIP_RILL_MODE" --argjson s "$resp" '{available:true,state:"healthy",mode:$mode}+$s'
    else
        jq -cn --arg mode "$CFIP_RILL_MODE" '{available:true,state:"error",rillVersion:"",mode:$mode}'
    fi
}

cfip_rill_rank_shadow() {
    local native_json="$1" output="$2" request tmp rc=0 response_bytes native_set rill_set created_at
    [[ "$CFIP_RILL_ENABLED" == true && "$CFIP_RILL_MODE" != off ]] || return 2
    [[ -x "$CFIP_RILL_ADAPTER" ]] || return 3
    request="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-request.XXXXXX")" || return 4
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-response.XXXXXX")" || { rm -f "$request"; return 4; }
    created_at="$(date +%s)"
    jq -n --arg runId "$CFIP_RUN_ID" --argjson createdAt "$created_at" --argjson candidates "$(cat "$native_json")" \
      '{schemaVersion:1,runId:$runId,createdAt:$createdAt,candidates:$candidates}' >"$request"
    if command -v timeout >/dev/null 2>&1; then
        timeout "${CFIP_RILL_TIMEOUT_S}s" "$CFIP_RILL_ADAPTER" rank --state "$CFIP_RILL_STATE" --input "$request" >"$tmp" 2>>"$CFIP_LOG_FILE" || rc=$?
    else
        cfip_run_with_timeout "$CFIP_RILL_TIMEOUT_S" "$CFIP_RILL_ADAPTER" rank --state "$CFIP_RILL_STATE" --input "$request" >"$tmp" 2>>"$CFIP_LOG_FILE" || rc=$?
    fi
    rm -f "$request"
    response_bytes="$(wc -c <"$tmp" 2>/dev/null || printf 0)"
    if ((rc != 0 || response_bytes > 262144)) || ! jq -e '.success==true and .rillVersion=="1.5.3" and .adapterProtocolVersion==1 and (.candidates|type=="array") and ((.candidates|length)<=128)' "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"; return 5
    fi
    native_set="$(jq -c '[.[].ip]|sort' "$native_json")"; rill_set="$(jq -c '[.candidates[].ip]|sort' "$tmp" 2>/dev/null || printf '[]')"
    [[ "$native_set" == "$rill_set" ]] || { rm -f "$tmp"; return 6; }
    mv "$tmp" "$output"
}

cfip_rill_feedback() {
    local decision_json="$1" outcome_json="$2" request rc=0 generation
    [[ "$CFIP_RILL_ENABLED" == true && -x "$CFIP_RILL_ADAPTER" ]] || return 0
    [[ "$(jq -r '.validated//false' "$outcome_json")" == true ]] || return 0
    generation="$(jq '.generation // null' "$decision_json")"; [[ "$generation" != null ]] || return 0
    request="$(mktemp "${TMPDIR:-/tmp}/cfip-rill-feedback.XXXXXX")" || return 1
    jq -n --arg runId "$CFIP_RUN_ID" --argjson generation "$generation" --argjson outcome "$(cat "$outcome_json")" \
      '{schemaVersion:1,decision:{runId:$runId,generation:$generation},outcome:$outcome}' >"$request"
    if command -v timeout >/dev/null 2>&1; then
        timeout "${CFIP_RILL_TIMEOUT_S}s" "$CFIP_RILL_ADAPTER" feedback --state "$CFIP_RILL_STATE" --input "$request" >/dev/null 2>>"$CFIP_LOG_FILE" || rc=$?
    else
        cfip_run_with_timeout "$CFIP_RILL_TIMEOUT_S" "$CFIP_RILL_ADAPTER" feedback --state "$CFIP_RILL_STATE" --input "$request" >/dev/null 2>>"$CFIP_LOG_FILE" || rc=$?
    fi
    rm -f "$request"; return "$rc"
}
