#!/usr/bin/env bash
# shellcheck shell=bash

CFIP_PUBLISH_DIR="${CFIP_PUBLISH_DIR:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publish}"
CFIP_PUBLISH_STATUS_FILE="${CFIP_PUBLISH_STATUS_FILE:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publisher-status.json}"
CFIP_PUBLISH_INIT="${CFIP_PUBLISH_INIT:-/etc/init.d/cf_ip_publisher}"

cfip_publish_result() {
    local selected="$1" run_id="${CFIP_RUN_ID:-}" tmp count bind port
    [[ "${CFIP_PUBLISH_ENABLED:-false}" == true ]] || { [[ -x "$CFIP_PUBLISH_INIT" ]] && "$CFIP_PUBLISH_INIT" stop >/dev/null 2>&1 || true; return 0; }
    [[ -s "$selected" ]] || return 2
    count="$(jq 'length' "$selected")"; ((count>0)) || return 2
    mkdir -p "$CFIP_PUBLISH_DIR"
    tmp="$(mktemp -d "${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/publish-next.XXXXXX")" || return 1
    jq -r '.[].ip' "$selected" >"$tmp/ip.txt"
    jq -r '.[]|select(.family=="ipv4")|.ip' "$selected" >"$tmp/best-ipv4.txt"
    jq -r '.[]|select(.family=="ipv6")|.ip' "$selected" >"$tmp/best-ipv6.txt"
    jq -n --arg runId "$run_id" --argjson selected "$(cat "$selected")" '{schemaVersion:1,runId:$runId,generatedAt:now,ips:[$selected[].ip],selected:$selected}' >"$tmp/result.json"
    chmod 644 "$tmp"/*.txt "$tmp/result.json" 2>/dev/null || true
    for f in ip.txt best-ipv4.txt best-ipv6.txt result.json; do cat "$tmp/$f" | cfip_atomic_write "$CFIP_PUBLISH_DIR/$f"; chmod 644 "$CFIP_PUBLISH_DIR/$f" 2>/dev/null || true; done
    rm -rf "$tmp"
    bind="${CFIP_PUBLISH_BIND:-}"; port="${CFIP_PUBLISH_PORT:-12345}"
    if [[ -x "$CFIP_PUBLISH_INIT" ]]; then
        "$CFIP_PUBLISH_INIT" restart >/dev/null 2>&1 || { jq -cn --arg bind "$bind" --argjson port "$port" '{success:false,error:"uhttpd_start_failed",bind:$bind,port:$port,observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"; return 3; }
    else
        jq -cn '{success:false,error:"publisher_init_missing",observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"; return 4
    fi
    jq -cn --arg bind "$bind" --argjson port "$port" --argjson count "$count" '{success:true,bind:(if $bind=="" then "lan-auto" else $bind end),port:$port,count:$count,paths:["/ip.txt","/best-ipv4.txt","/best-ipv6.txt","/result.json"],observedAt:now}' | cfip_atomic_write "$CFIP_PUBLISH_STATUS_FILE"
}

cfip_publisher_status_json() {
    [[ -s "$CFIP_PUBLISH_STATUS_FILE" ]] && cat "$CFIP_PUBLISH_STATUS_FILE" || printf '{"success":false,"state":"disabled_or_not_started"}'
}
