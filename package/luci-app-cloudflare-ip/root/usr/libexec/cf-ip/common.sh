#!/usr/bin/env bash
# shellcheck shell=bash

cfip_log() {
    local msg="$*" ts
    ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
    mkdir -p "${CFIP_LOG_FILE%/*}" 2>/dev/null || true
    printf '[%s] %s\n' "$ts" "$msg" >>"$CFIP_LOG_FILE" 2>/dev/null || true
    [[ "${CFIP_VERBOSE:-false}" == true ]] && printf '[cloudflare-ip] %s\n' "$msg" >&2 || true
}

cfip_json_error() {
    jq -cn --arg error "$1" '{success:false,error:$error}'
}

cfip_bool() {
    case "${1:-}" in 1|on|true|yes|enabled) printf true ;; *) printf false ;; esac
}

cfip_atomic_write() {
    local output="$1" tmp
    mkdir -p "${output%/*}" 2>/dev/null || true
    tmp="$(mktemp "${output}.tmp.XXXXXX")" || return 1
    cat >"$tmp" || { rm -f "$tmp"; return 1; }
    chmod 600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$output"
}

cfip_generate_run_id() {
    local now rand
    now="$(date +%s 2>/dev/null || printf 0)"
    rand="${RANDOM:-0}"
    printf '%s-%s-%s' "$now" "$$" "$rand"
}

cfip_is_ipv4() {
    local ip="$1" IFS=. octets i
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    read -r -a octets <<<"$ip"
    ((${#octets[@]} == 4)) || return 1
    for i in "${octets[@]}"; do [[ "$i" =~ ^[0-9]+$ ]] && ((10#$i <= 255)) || return 1; done
}

cfip_is_ipv6() {
    local ip="$1"
    [[ "$ip" == *:* && "$ip" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    declare -F cfip_expand_ipv6_hex >/dev/null 2>&1 || return 1
    cfip_expand_ipv6_hex "$ip" >/dev/null 2>&1
}

cfip_ip_family() {
    cfip_is_ipv4 "$1" && { printf ipv4; return 0; }
    cfip_is_ipv6 "$1" && { printf ipv6; return 0; }
    return 1
}

cfip_is_public_candidate() {
    local ip="$1" first second third fourth
    if cfip_is_ipv4 "$ip"; then
        IFS=. read -r first second third fourth <<<"$ip"
        ((first >= 1 && first <= 223)) || return 1
        ((first == 10)) && return 1
        ((first == 100 && second >= 64 && second <= 127)) && return 1
        ((first == 127 || first == 169 && second == 254)) && return 1
        ((first == 172 && second >= 16 && second <= 31)) && return 1
        ((first == 192 && second == 168)) && return 1
        ((first == 192 && second == 0 && third == 0)) && return 1
        ((first == 192 && second == 0 && third == 2)) && return 1
        ((first == 198 && second == 18 || first == 198 && second == 19)) && return 1
        ((first == 198 && second == 51 && third == 100)) && return 1
        ((first == 203 && second == 0 && third == 113)) && return 1
        ((first >= 224)) && return 1
        return 0
    fi
    cfip_is_ipv6 "$ip" || return 1
    local hex
    hex="$(cfip_expand_ipv6_hex "$ip")" || return 1
    [[ "$hex" != 00000000000000000000000000000000 && "$hex" != 00000000000000000000000000000001 ]] || return 1
    [[ "$hex" != 00000000000000000000ffff* ]] || return 1
    case "${hex:0:2}" in fc|fd|fe|ff) return 1 ;; esac
    [[ "${hex:0:8}" != 20010db8* ]] || return 1
    return 0
}

cfip_normalize_domain_list() {
    local input="$1" out=() raw d
    IFS=',' read -r -a raw <<<"$input"
    for d in "${raw[@]}"; do
        d="${d#${d%%[![:space:]]*}}"; d="${d%${d##*[![:space:]]}}"
        [[ -n "$d" && ${#d} -le 253 && "$d" =~ ^[A-Za-z0-9._-]+$ && "$d" == *.* ]] || continue
        out+=("$d")
    done
    ((${#out[@]} > 0)) || return 1
    local IFS=,
    printf '%s' "${out[*]}"
}

cfip_https_url_or_empty() {
    [[ -z "${1:-}" || "$1" =~ ^https://[^[:space:][:cntrl:]]+$ ]]
}

cfip_valid_cron() {
    local expr="$1" f1 f2 f3 f4 f5 extra
    [[ -n "$expr" && "$expr" != *$'\n'* && "$expr" != *$'\r'* ]] || return 1
    [[ "$expr" =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)$ ]] || return 1
    f1="${BASH_REMATCH[1]}"; f2="${BASH_REMATCH[2]}"; f3="${BASH_REMATCH[3]}"; f4="${BASH_REMATCH[4]}"; f5="${BASH_REMATCH[5]}"
    for extra in "$f1" "$f2" "$f3" "$f4" "$f5"; do [[ "$extra" =~ ^[0-9*/?,\-]+$ ]] || return 1; done
}

cfip_service_running() {
    local service="$1"
    [[ -x "/etc/init.d/$service" ]] || return 1
    "/etc/init.d/$service" running >/dev/null 2>&1 || { [[ "$service" == openclash ]] && pidof clash >/dev/null 2>&1; }
}

cfip_stop_service() {
    local service="$1"
    [[ -x "/etc/init.d/$service" ]] || return 1
    if [[ "$service" == openclash ]]; then
        CFIP_OPENCLASH_ENABLE_SAVED="$(uci -q get openclash.config.enable 2>/dev/null || printf 1)"
        uci -q set openclash.config.enable=0
        uci -q commit openclash
    fi
    "/etc/init.d/$service" stop >/dev/null 2>&1 || return 1
    if [[ "$service" == openclash ]]; then
        local i pids
        for i in $(seq 1 30); do
            [[ "$(cfip_deadline_remaining)" -gt 0 ]] || return 1
            pids="$(pidof clash 2>/dev/null || true)"
            [[ -z "$pids" ]] && return 0
            sleep 1
        done
        pids="$(pidof clash 2>/dev/null || true)"
        if [[ -n "$pids" ]]; then
            # shellcheck disable=SC2086
            kill -TERM $pids 2>/dev/null || true
            sleep 1
            pids="$(pidof clash 2>/dev/null || true)"
            # shellcheck disable=SC2086
            [[ -z "$pids" ]] || kill -KILL $pids 2>/dev/null || true
        fi
        [[ -z "$(pidof clash 2>/dev/null || true)" ]]
    fi
}

cfip_restart_service() {
    local service="$1"
    [[ -x "/etc/init.d/$service" ]] || return 1
    if [[ "$service" == openclash && -n "${CFIP_OPENCLASH_ENABLE_SAVED:-}" ]]; then
        uci -q set "openclash.config.enable=${CFIP_OPENCLASH_ENABLE_SAVED}"
        uci -q commit openclash
    fi
    "/etc/init.d/$service" restart >/dev/null 2>&1 || return 1
    local i
    for i in $(seq 1 20); do
        [[ "$(cfip_deadline_remaining)" -gt 0 ]] || return 1
        cfip_service_running "$service" && return 0
        sleep 1
    done
    return 1
}

cfip_read_log_json() {
    local content=""
    [[ -f "$CFIP_LOG_FILE" ]] && content="$(tail -n 500 "$CFIP_LOG_FILE" 2>/dev/null || true)"
    jq -cn --arg logs "$content" '{success:true,logs:$logs}'
}

cfip_now_epoch() { date +%s 2>/dev/null || printf 0; }

cfip_deadline_remaining() {
    local deadline="${CFIP_MEASUREMENT_DEADLINE:-0}" now
    ((deadline>0)) || { printf 86400; return 0; }
    now="$(cfip_now_epoch)"
    ((deadline>now)) && printf '%s' "$((deadline-now))" || printf 0
}

# Portable watchdog for OpenWrt/Bash; does not require coreutils timeout.
# Returns 124 when the watchdog expires.
cfip_run_with_timeout() {
    local limit="$1" marker pid watcher rc
    shift
    [[ "$limit" =~ ^[1-9][0-9]*$ ]] || return 2
    marker="$(mktemp "${TMPDIR:-/tmp}/cfip-timeout.XXXXXX")" || return 2
    rm -f "$marker"
    "$@" & pid=$!
    (
        sleep "$limit"
        if kill -0 "$pid" 2>/dev/null; then
            : >"$marker"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
        fi
    ) & watcher=$!
    rc=0; wait "$pid" 2>/dev/null || rc=$?
    kill "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    if [[ -f "$marker" ]]; then rm -f "$marker"; return 124; fi
    rm -f "$marker"
    return "$rc"
}
