#!/usr/bin/env bash
# shellcheck shell=bash

# Candidate Source Engine.
# Contract: every CFST input produced here is a plain IP expressed as /32 or /128.
# Remote labels/ports are provenance only; domains are rejected.

CFIP_SOURCE_CACHE_DIR="${CFIP_SOURCE_CACHE_DIR:-${CFIP_STATUS_DIR:-/etc/cf_ip}/sources}"
CFIP_SOURCE_RUNTIME_DIR="${CFIP_SOURCE_RUNTIME_DIR:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/sources}"
CFIP_SOURCE_MAX_BYTES="${CFIP_SOURCE_MAX_BYTES:-524288}"
CFIP_SOURCE_MAX_LINES="${CFIP_SOURCE_MAX_LINES:-4096}"
CFIP_SOURCE_CONNECT_TIMEOUT="${CFIP_SOURCE_CONNECT_TIMEOUT:-5}"
CFIP_SOURCE_TOTAL_TIMEOUT="${CFIP_SOURCE_TOTAL_TIMEOUT:-15}"
CFIP_SOURCE_MAX_COUNT="${CFIP_SOURCE_MAX_COUNT:-16}"
CFIP_SOURCE_MAX_VALID_PER_SOURCE="${CFIP_SOURCE_MAX_VALID_PER_SOURCE:-2048}"
CFIP_SOURCE_MIN_VALID_REMOTE="${CFIP_SOURCE_MIN_VALID_REMOTE:-2}"
CFIP_HISTORY_MAX_AGE_SECONDS="${CFIP_HISTORY_MAX_AGE_SECONDS:-604800}"
CFIP_SOURCE_POLICY="${CFIP_SOURCE_POLICY:-balanced}"
CFIP_SOURCE_POLICY_EFFECTIVE="${CFIP_SOURCE_POLICY_EFFECTIVE:-$CFIP_SOURCE_POLICY}"
CFIP_SOURCE_USED_COUNT=0
CFIP_SOURCE_REFRESH_DEADLINE=0

cfip_source_policy_registry_json() {
    cat <<'JSON'
[
  {"id":"balanced","official":0.50,"community":0.30,"carrier":0.10,"measured":0.10},
  {"id":"official-heavy","official":0.75,"community":0.10,"carrier":0.05,"measured":0.10},
  {"id":"history-heavy","official":0.35,"community":0.35,"carrier":0.10,"measured":0.20},
  {"id":"diversity-heavy","official":0.35,"community":0.25,"carrier":0.25,"measured":0.15},
  {"id":"community-heavy","official":0.35,"community":0.45,"carrier":0.15,"measured":0.05}
]
JSON
}

cfip_source_policy_valid() { cfip_source_policy_registry_json | jq -e --arg id "${1:-}" 'any(.[];.id==$id)' >/dev/null 2>&1; }

cfip_source_policy_json() {
    local registry policy
    registry="$(cfip_source_policy_registry_json)"
    policy="$CFIP_SOURCE_POLICY_EFFECTIVE"
    cfip_source_policy_valid "$policy" || policy=balanced
    jq -cn --arg requested "$CFIP_SOURCE_POLICY" --arg effective "$policy" --argjson registry "$registry" '{requested:$requested,effective:$effective,registry:$registry,deterministic:true}'
}

cfip_source_policy_order() {
    local ids="$1" policy="${CFIP_SOURCE_POLICY_EFFECTIVE:-${CFIP_SOURCE_POLICY:-balanced}}"
    cfip_source_policy_valid "$policy" || policy=balanced
    jq -rn --arg ids "$ids" --arg policy "$policy" --argjson registry "$(cfip_source_policy_registry_json)" '
      ($registry|map(select(.id==$policy))[0] // $registry[0]) as $p |
      ($ids|split(" ")|map(select(length>0))) as $ids |
      ($ids|to_entries|map({id:.value,index:.key,rank:(if (.value|test("official")) then $p.official elif (.value|test("carrier")) then $p.carrier elif (.value|test("svips")) then $p.measured else $p.community end)})|sort_by(-.rank,.index)|map(.id)|join(" "))
    '
}

cfip_builtin_registry_json() {
    cat <<'JSON'
[
  {"id":"cloudflare-official-v4","name":"Cloudflare Official IPv4","group":"official","sourceClass":"official","family":"ipv4","parser":"cidr","url":"https://www.cloudflare.com/ips-v4","defaultEnabled":true},
  {"id":"cloudflare-official-v6","name":"Cloudflare Official IPv6","group":"official","sourceClass":"official","family":"ipv6","parser":"cidr","url":"https://www.cloudflare.com/ips-v6","defaultEnabled":true},
  {"id":"lancelotrar-best-cf-ipv4","name":"LancelotRar best-cf-ips","group":"recommended","sourceClass":"community","family":"ipv4","parser":"ip-text","url":"https://raw.githubusercontent.com/LancelotRar/best-cf-ips/main/best-cf-ipv4.txt","defaultEnabled":false},
  {"id":"ipdb-bestcf-v4","name":"IPDB BestCF IPv4","group":"recommended","sourceClass":"community","family":"ipv4","parser":"ip-text","url":"https://ipdb.api.030101.xyz/?type=bestcfv4","defaultEnabled":false},
  {"id":"ipdb-bestcf-v6","name":"IPDB BestCF IPv6","group":"recommended","sourceClass":"community","family":"ipv6","parser":"ip-text","url":"https://ipdb.api.030101.xyz/?type=bestcfv6","defaultEnabled":false},
  {"id":"dustinwin-bestcf-generic","name":"DustinWin BestCF","group":"recommended","sourceClass":"community","family":"auto","parser":"ip-text","url":"https://raw.githubusercontent.com/DustinWin/BestCF/bestcf/bestcf-ip.txt","defaultEnabled":false},
  {"id":"dustinwin-bestcf-cmcc","name":"DustinWin BestCF CMCC","group":"carrier","sourceClass":"community","family":"auto","parser":"ip-text","url":"https://raw.githubusercontent.com/DustinWin/BestCF/bestcf/cmcc-ip.txt","defaultEnabled":false},
  {"id":"dustinwin-bestcf-cucc","name":"DustinWin BestCF CUCC","group":"carrier","sourceClass":"community","family":"auto","parser":"ip-text","url":"https://raw.githubusercontent.com/DustinWin/BestCF/bestcf/cucc-ip.txt","defaultEnabled":false},
  {"id":"dustinwin-bestcf-ctcc","name":"DustinWin BestCF CTCC","group":"carrier","sourceClass":"community","family":"auto","parser":"ip-text","url":"https://raw.githubusercontent.com/DustinWin/BestCF/bestcf/ctcc-ip.txt","defaultEnabled":false},
  {"id":"svips-best-ips","name":"svip-s measured seed IPs","group":"measured","sourceClass":"community","family":"ipv4","parser":"ip-text","url":"https://raw.githubusercontent.com/svip-s/cloudflare_ip/main/best_ips.txt","defaultEnabled":false}
]
JSON
}

cfip_builtin_source_json() {
    local id="$1"
    cfip_builtin_registry_json | jq -c --arg id "$id" '.[] | select(.id==$id)' | head -n1
}

cfip_source_family_allowed() {
    local family="$1"
    case "${CFIP_IP_TYPE:-ipv4}:$family" in
      ipv4:ipv4|ipv6:ipv6|both:ipv4|both:ipv6|*:auto) return 0 ;;
      *) return 1 ;;
    esac
}

cfip_trim() {
    local s="${1:-}"
    s="${s#${s%%[![:space:]]*}}"
    s="${s%${s##*[![:space:]]}}"
    printf '%s' "$s"
}

cfip_valid_cidr() {
    local cidr="$1" addr prefix fam
    [[ "$cidr" == */* ]] || return 1
    addr="${cidr%/*}"; prefix="${cidr##*/}"
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    if cfip_is_ipv4 "$addr"; then ((prefix>=0 && prefix<=32)); return; fi
    if cfip_is_ipv6 "$addr"; then ((prefix>=0 && prefix<=128)); return; fi
    return 1
}

# Extract only an IP from a community text line. Ports and labels are intentionally discarded.
# Domain-only lines fail closed.
cfip_extract_ip_line() {
    local line token ip
    line="${1//$'\r'/}"
    line="$(cfip_trim "$line")"
    [[ -n "$line" ]] || return 1
    [[ "$line" == \#* || "$line" == \;* ]] && return 1
    token="${line%%[[:space:]]*}"
    token="${token%%#*}"
    token="${token%%,*}"
    token="$(cfip_trim "$token")"
    [[ -n "$token" ]] || return 1

    # [IPv6]:port or [IPv6]
    if [[ "$token" =~ ^\[([0-9A-Fa-f:]+)\](:[0-9]+)?$ ]]; then
        ip="${BASH_REMATCH[1]}"
        cfip_is_ipv6 "$ip" && { printf '%s' "$ip"; return 0; }
        return 1
    fi
    # IPv4:port
    if [[ "$token" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):[0-9]+$ ]]; then
        ip="${BASH_REMATCH[1]}"
        cfip_is_ipv4 "$ip" && { printf '%s' "$ip"; return 0; }
        return 1
    fi
    cfip_is_ipv4 "$token" && { printf '%s' "$token"; return 0; }
    cfip_is_ipv6 "$token" && { printf '%s' "$token"; return 0; }
    return 1
}

cfip_parse_source_file() {
    local file="$1" parser="$2" source_id="$3" source_class="$4" family_hint="$5" stale="$6" output="$7"
    local tmp line value fam count=0 rejected=0
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-source.XXXXXX")" || return 1
    printf '[]' >"$tmp"
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((count + rejected >= CFIP_SOURCE_MAX_LINES || count >= CFIP_SOURCE_MAX_VALID_PER_SOURCE)) && break
        line="${line//$'\r'/}"
        [[ -n "$(cfip_trim "$line")" ]] || continue
        if [[ "$parser" == cidr ]]; then
            value="${line%%[[:space:]#]*}"
            value="$(cfip_trim "$value")"
            if ! cfip_valid_cidr "$value"; then rejected=$((rejected+1)); continue; fi
            fam="$(cfip_ip_family "${value%/*}")" || { rejected=$((rejected+1)); continue; }
            cfip_is_public_candidate "${value%/*}" || { rejected=$((rejected+1)); continue; }
            cfip_source_family_allowed "$fam" || continue
            if [[ "$family_hint" != auto && "$family_hint" != both && "$family_hint" != "$fam" ]]; then rejected=$((rejected+1)); continue; fi
            jq -c --arg value "$value" --arg family "$fam" --arg sourceId "$source_id" --arg sourceClass "$source_class" --argjson stale "$stale" \
              '. + [{kind:"cidr",value:$value,family:$family,sourceId:$sourceId,sourceClass:$sourceClass,stale:$stale}]' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp"
            count=$((count+1))
        else
            if value="$(cfip_extract_ip_line "$line")"; then
                fam="$(cfip_ip_family "$value")" || { rejected=$((rejected+1)); continue; }
                cfip_is_public_candidate "$value" || { rejected=$((rejected+1)); continue; }
                cfip_source_family_allowed "$fam" || continue
                if [[ "$family_hint" != auto && "$family_hint" != both && "$family_hint" != "$fam" ]]; then rejected=$((rejected+1)); continue; fi
                jq -c --arg ip "$value" --arg family "$fam" --arg sourceId "$source_id" --arg sourceClass "$source_class" --argjson stale "$stale" \
                  '. + [{kind:"ip",value:$ip,family:$family,sourceId:$sourceId,sourceClass:$sourceClass,stale:$stale}]' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp"
                count=$((count+1))
            elif value="${line%%[[:space:]#]*}"; cfip_valid_cidr "$value"; then
                fam="$(cfip_ip_family "${value%/*}")" || { rejected=$((rejected+1)); continue; }
                cfip_is_public_candidate "${value%/*}" || { rejected=$((rejected+1)); continue; }
                cfip_source_family_allowed "$fam" || continue
                jq -c --arg value "$value" --arg family "$fam" --arg sourceId "$source_id" --arg sourceClass "$source_class" --argjson stale "$stale" \
                  '. + [{kind:"cidr",value:$value,family:$family,sourceId:$sourceId,sourceClass:$sourceClass,stale:$stale}]' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp"
                count=$((count+1))
            else
                rejected=$((rejected+1))
            fi
        fi
    done <"$file"
    jq --argjson rejected "$rejected" --argjson parsed "$count" '{records:.,parsedCount:$parsed,rejectedCount:$rejected}' "$tmp" | cfip_atomic_write "$output"
    rm -f "$tmp"
}

cfip_source_meta_write() {
    local id="$1" success="$2" stale="$3" from_cache="$4" parsed="$5" rejected="$6" error="$7" hash="$8" meta
    meta="$CFIP_SOURCE_RUNTIME_DIR/$id/metadata.json"
    mkdir -p "${meta%/*}"
    jq -cn --arg id "$id" --arg error "$error" --arg hash "$hash" --argjson success "$success" --argjson stale "$stale" --argjson fromCache "$from_cache" --argjson parsed "$parsed" --argjson rejected "$rejected" \
      '{schemaVersion:1,id:$id,success:$success,stale:$stale,fromCache:$fromCache,parsedCount:$parsed,rejectedCount:$rejected,lastError:(if $error=="" then null else $error end),contentHash:(if $hash=="" then null else $hash end),observedAt:now}' | cfip_atomic_write "$meta"
}

cfip_source_curl_max_filesize_supported() {
    case "${CFIP_SOURCE_CURL_MAX_FILESIZE_SUPPORTED:-}" in
        true) return 0 ;;
        false) return 1 ;;
    esac
    if command curl --help all 2>&1 | grep -q -- '--max-filesize'; then
        CFIP_SOURCE_CURL_MAX_FILESIZE_SUPPORTED=true
        return 0
    fi
    CFIP_SOURCE_CURL_MAX_FILESIZE_SUPPORTED=false
    return 1
}

cfip_source_refresh_remaining() {
    local now
    [[ "${CFIP_SOURCE_REFRESH_DEADLINE:-0}" =~ ^[0-9]+$ ]] || return 1
    ((CFIP_SOURCE_REFRESH_DEADLINE > 0)) || { printf '%s' "${CFIP_SOURCE_TOTAL_TIMEOUT:-15}"; return 0; }
    now="$(cfip_monotonic_seconds 2>/dev/null || date +%s)"
    printf '%s' "$((CFIP_SOURCE_REFRESH_DEADLINE-now))"
}

cfip_source_fetch_remote() {
    local id="$1" url="$2" parser="$3" family="$4" source_class="$5" output="$6"
    local rdir pdir tmp raw parsed bytes lines hash="" oldhash="" pc=0 rc=0 error="" remaining connect_timeout
    rdir="$CFIP_SOURCE_RUNTIME_DIR/$id"; pdir="$CFIP_SOURCE_CACHE_DIR/$id"
    mkdir -p "$rdir" "$pdir"
    tmp="$(mktemp "$rdir/fetch.XXXXXX")" || return 1
    raw="$pdir/last-good.txt"
    parsed="$rdir/parsed.json"
    remaining="$(cfip_source_refresh_remaining)"
    if ! [[ "$remaining" =~ ^[0-9]+$ ]] || ((remaining <= 0)); then
        cfip_source_meta_write "$id" false true false 0 0 source_refresh_deadline ""
        printf '[]' | cfip_atomic_write "$output"
        rm -f "$tmp"
        return 1
    fi
    connect_timeout="${CFIP_SOURCE_CONNECT_TIMEOUT:-5}"
    [[ "$connect_timeout" =~ ^[0-9]+$ ]] || connect_timeout=5
    ((connect_timeout > remaining)) && connect_timeout="$remaining"
    if if cfip_source_curl_max_filesize_supported; then
        curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout "$connect_timeout" --max-time "$remaining" --max-redirs 3 --max-filesize "$CFIP_SOURCE_MAX_BYTES" "$url" -o "$tmp" 2>/dev/null
    else
        curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout "$connect_timeout" --max-time "$remaining" --max-redirs 3 "$url" -o "$tmp" 2>/dev/null
    fi; then
        bytes="$(wc -c <"$tmp" 2>/dev/null || printf 999999999)"; lines="$(wc -l <"$tmp" 2>/dev/null || printf 999999999)"
        if ((bytes <= CFIP_SOURCE_MAX_BYTES && lines <= CFIP_SOURCE_MAX_LINES)); then
            cfip_parse_source_file "$tmp" "$parser" "$id" "$source_class" "$family" false "$parsed" || error=parse_failed
            pc="$(jq -r '.parsedCount//0' "$parsed" 2>/dev/null || printf 0)"; rc="$(jq -r '.rejectedCount//0' "$parsed" 2>/dev/null || printf 0)"
            if ((pc >= CFIP_SOURCE_MIN_VALID_REMOTE)); then
                hash="$(sha256sum "$tmp" | awk '{print $1}')"
                [[ -f "$pdir/metadata.json" ]] && oldhash="$(jq -r '.contentHash//empty' "$pdir/metadata.json" 2>/dev/null || true)"
                if [[ "$hash" != "$oldhash" || ! -s "$raw" || ! -s "$pdir/metadata.json" ]]; then
                    cat "$tmp" | cfip_atomic_write "$raw"
                    jq -cn --arg id "$id" --arg hash "$hash" --arg url "$url" --argjson parsed "$pc" --argjson rejected "$rc" '{schemaVersion:1,id:$id,url:$url,contentHash:$hash,parsedCount:$parsed,rejectedCount:$rejected,lastSuccessAt:now}' | cfip_atomic_write "$pdir/metadata.json"
                fi
                cfip_source_meta_write "$id" true false false "$pc" "$rc" "" "$hash"
                jq '.records' "$parsed" | cfip_atomic_write "$output"
                rm -f "$tmp"
                return 0
            fi
            error="${error:-too_few_valid_candidates}"
        else
            error=source_too_large
        fi
    else
        error=fetch_failed
    fi
    rm -f "$tmp"

    # Fail over to persistent last-good data, never to an unvalidated partial fetch.
    if [[ -s "$raw" ]]; then
        cfip_parse_source_file "$raw" "$parser" "$id" "$source_class" "$family" true "$parsed" || true
        pc="$(jq -r '.parsedCount//0' "$parsed" 2>/dev/null || printf 0)"; rc="$(jq -r '.rejectedCount//0' "$parsed" 2>/dev/null || printf 0)"
        if ((pc >= CFIP_SOURCE_MIN_VALID_REMOTE)); then
            hash="$(sha256sum "$raw" | awk '{print $1}')"
            cfip_source_meta_write "$id" true true true "$pc" "$rc" "$error" "$hash"
            jq '.records' "$parsed" | cfip_atomic_write "$output"
            return 0
        fi
    fi
    cfip_source_meta_write "$id" false true false 0 0 "$error" ""
    printf '[]' | cfip_atomic_write "$output"
    return 1
}

cfip_source_collect_custom() {
    local aggregate="$1" status="$2" section enabled kind name url family parser ips id tmp raw parsed source_class=community remaining
    while IFS= read -r section; do
        [[ -n "$section" ]] || continue
        ((CFIP_SOURCE_USED_COUNT < CFIP_SOURCE_MAX_COUNT)) || break
        remaining="$(cfip_source_refresh_remaining 2>/dev/null || printf 0)"
        [[ "$remaining" =~ ^[0-9]+$ ]] && ((remaining > 0)) || break
        enabled="$(uci -q get "cf_ip.$section.enabled" 2>/dev/null || printf 0)"
        [[ "$(cfip_bool "$enabled")" == true ]] || continue
        CFIP_SOURCE_USED_COUNT=$((CFIP_SOURCE_USED_COUNT+1))
        id="custom-$section"; kind="$(uci -q get "cf_ip.$section.kind" 2>/dev/null || printf url)"; name="$(uci -q get "cf_ip.$section.name" 2>/dev/null || printf '%s' "$section")"; family="$(uci -q get "cf_ip.$section.family" 2>/dev/null || printf auto)"; parser="$(uci -q get "cf_ip.$section.parser" 2>/dev/null || printf ip-text)"
        cfip_source_family_allowed "$family" || [[ "$family" == auto ]] || continue
        tmp="$CFIP_SOURCE_RUNTIME_DIR/$id/records.json"; mkdir -p "${tmp%/*}"
        if [[ "$kind" == manual ]]; then
            raw="$CFIP_SOURCE_RUNTIME_DIR/$id/manual.txt"; : >"$raw"
            ips="$(uci -q get "cf_ip.$section.ip" 2>/dev/null || true)"
            for value in $ips; do printf '%s\n' "$value" >>"$raw"; done
            parsed="$CFIP_SOURCE_RUNTIME_DIR/$id/parsed.json"
            cfip_parse_source_file "$raw" ip-text "$id" "$source_class" "$family" false "$parsed" || true
            jq '.records' "$parsed" | cfip_atomic_write "$tmp"
            cfip_source_meta_write "$id" true false false "$(jq -r '.parsedCount//0' "$parsed")" "$(jq -r '.rejectedCount//0' "$parsed")" "" ""
        else
            url="$(uci -q get "cf_ip.$section.url" 2>/dev/null || true)"
            if ! cfip_https_url_or_empty "$url" || [[ -z "$url" ]]; then cfip_source_meta_write "$id" false true false 0 0 invalid_url ""; printf '[]' >"$tmp"; else cfip_source_fetch_remote "$id" "$url" "$parser" "$family" "$source_class" "$tmp" || true; fi
        fi
        jq -s '.[0] + .[1]' "$aggregate" "$tmp" >"$aggregate.next" && mv "$aggregate.next" "$aggregate"
    done < <(uci -q show cf_ip 2>/dev/null | sed -n "s/^cf_ip\.\([^.=]*\)=source$/\1/p")
}

cfip_collect_enabled_sources() {
    local output="$1" status_output="$2" ids="${CFIP_BUILTIN_SOURCES:-cloudflare-official-v4 cloudflare-official-v6}" id entry family url parser source_class tmp aggregate remaining
    ids="$(cfip_source_policy_order "$ids")"
    local refresh_started
    refresh_started="$(cfip_monotonic_seconds 2>/dev/null || date +%s)"
    CFIP_SOURCE_REFRESH_DEADLINE=$((refresh_started + ${CFIP_SOURCE_TOTAL_TIMEOUT:-15}))
    mkdir -p "$CFIP_SOURCE_RUNTIME_DIR" "$CFIP_SOURCE_CACHE_DIR"
    aggregate="$(mktemp "${TMPDIR:-/tmp}/cfip-all-sources.XXXXXX")" || return 1
    printf '[]' >"$aggregate"; CFIP_SOURCE_USED_COUNT=0
    for id in $ids; do
        ((CFIP_SOURCE_USED_COUNT < CFIP_SOURCE_MAX_COUNT)) || break
        remaining="$(cfip_source_refresh_remaining 2>/dev/null || printf 0)"
        [[ "$remaining" =~ ^[0-9]+$ ]] && ((remaining > 0)) || break
        entry="$(cfip_builtin_source_json "$id")"; [[ -n "$entry" ]] || continue
        CFIP_SOURCE_USED_COUNT=$((CFIP_SOURCE_USED_COUNT+1))
        family="$(jq -r '.family' <<<"$entry")"; cfip_source_family_allowed "$family" || [[ "$family" == auto ]] || continue
        url="$(jq -r '.url' <<<"$entry")"; parser="$(jq -r '.parser' <<<"$entry")"; source_class="$(jq -r '.sourceClass' <<<"$entry")"
        tmp="$CFIP_SOURCE_RUNTIME_DIR/$id/records.json"; mkdir -p "${tmp%/*}"
        cfip_source_fetch_remote "$id" "$url" "$parser" "$family" "$source_class" "$tmp" || true
        jq -s '.[0] + .[1]' "$aggregate" "$tmp" >"$aggregate.next" && mv "$aggregate.next" "$aggregate"
    done
    cfip_source_collect_custom "$aggregate" "$status_output"
    cat "$aggregate" | cfip_atomic_write "$output"
    rm -f "$aggregate"
    # Runtime status is composed from per-source metadata; no remote content is embedded.
    local metas=() mf
    while IFS= read -r mf; do metas+=("$mf"); done < <(find "$CFIP_SOURCE_RUNTIME_DIR" -mindepth 2 -maxdepth 2 -name metadata.json -type f 2>/dev/null | sort)
    if ((${#metas[@]}>0)); then jq -s 'sort_by(.id)' "${metas[@]}" | cfip_atomic_write "$status_output"; else printf '[]' | cfip_atomic_write "$status_output"; fi
}

cfip_history_pool_json() {
    local output="$1" max_age now cutoff
    max_age="${CFIP_HISTORY_MAX_AGE_SECONDS:-604800}"
    [[ "$max_age" =~ ^[0-9]+$ ]] || max_age=604800
    now="$(cfip_now_epoch 2>/dev/null || date +%s)"
    cutoff=$((now-max_age))
    if [[ -s "${CFIP_RUN_HISTORY:-}" ]]; then
        jq -s --argjson cutoff "$cutoff" '[.[] | select(.result=="success") | . as $r | (.bestIps[]? | {ip:.,time:($r.time//0)}) | select((.time|type)=="number" and .time >= $cutoff)]
          | group_by(.ip)
          | map({ip:.[0].ip,wins:length,lastSeen:(map(.time)|max),family:(if .[0].ip|contains(":") then "ipv6" else "ipv4" end)})
          | sort_by(-.wins,-.lastSeen,.ip)' "$CFIP_RUN_HISTORY" 2>/dev/null | cfip_atomic_write "$output" || printf '[]' | cfip_atomic_write "$output"
    else
        printf '[]' | cfip_atomic_write "$output"
    fi
}

cfip_expand_ipv6_hex() {
    local addr left right missing=0 g i out="" lg_count=0 rg_count=0
    local -a groups
    local -a lg
    local -a rg
    groups=(); lg=(); rg=()
    addr="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    [[ "$addr" != *:::* && "$addr" != *::*::* ]] || return 1
    if [[ "$addr" == *::* ]]; then
        left="${addr%%::*}"; right="${addr##*::}"
        if [[ -n "$left" ]]; then
            IFS=: read -r -a lg <<<"$left"
            lg_count=${#lg[@]}
        fi
        if [[ -n "$right" ]]; then
            IFS=: read -r -a rg <<<"$right"
            rg_count=${#rg[@]}
        fi
        missing=$((8-lg_count-rg_count)); ((missing>=1)) || return 1
        [[ "$lg_count" -eq 0 ]] || groups=("${lg[@]}")
        for ((i=0;i<missing;i++)); do groups+=(0); done
        [[ -n "$right" ]] && groups+=("${rg[@]}")
    else
        IFS=: read -r -a groups <<<"$addr"; ((${#groups[@]}==8)) || return 1
    fi
    for g in "${groups[@]}"; do [[ "$g" =~ ^[0-9a-f]{1,4}$ ]] || return 1; printf -v g '%04x' "$((16#$g))"; out+="$g"; done
    printf '%s' "$out"
}

cfip_ipv6_hex_to_full() {
    local hex="$1" out="" i
    ((${#hex}==32)) || return 1
    for ((i=0;i<32;i+=4)); do [[ -n "$out" ]] && out+=:; out+="${hex:i:4}"; done
    printf '%s' "$out"
}

cfip_sample_ipv4_cidr() {
    local cidr="$1" seed="${2:-${CFIP_SAMPLE_SEED:-0}}" addr prefix base size r offset value hash
    addr="${cidr%/*}"; prefix="${cidr##*/}"
    base="$(awk -F. '{printf "%.0f", (($1*256+$2)*256+$3)*256+$4}' <<<"$addr")" || return 1
    size="$(awk -v p="$prefix" 'BEGIN{printf "%.0f",2^(32-p)}')" || return 1
    hash="$(printf '%s' "$seed:$cidr" | sha256sum | awk '{print substr($1,1,8)}')" || return 1
    r=$((16#$hash))
    offset=$((r % size)); value=$((base - (base % size) + offset))
    awk -v n="$value" 'BEGIN{a=int(n/16777216)%256;b=int(n/65536)%256;c=int(n/256)%256;d=n%256;printf "%d.%d.%d.%d",a,b,c,d}'
}

cfip_sample_ipv6_cidr() {
    local cidr="$1" seed="${2:-${CFIP_SAMPLE_SEED:-0}}" addr prefix hex fixed rem i nib orig mask lowbits rand new out="" hash
    addr="${cidr%/*}"; prefix="${cidr##*/}"
    hex="$(cfip_expand_ipv6_hex "$addr")" || return 1
    fixed=$((prefix/4)); rem=$((prefix%4))
    hash="$(printf '%s' "$seed:$cidr" | sha256sum | awk '{print $1}')" || return 1
    for ((i=0;i<32;i++)); do
        nib="${hex:i:1}"
        if ((i<fixed)); then out+="$nib"; continue; fi
        if ((i==fixed && rem>0)); then
            orig=$((16#$nib)); mask=$(( (0xF << (4-rem)) & 0xF )); lowbits=$(( (1 << (4-rem)) - 1 )); rand=$((16#${hash:i:1} & lowbits)); new=$(( (orig & mask) | rand )); printf -v nib '%x' "$new"; out+="$nib"; continue
        fi
        printf -v nib '%x' "$((16#${hash:i:1} & 15))"; out+="$nib"
    done
    cfip_ipv6_hex_to_full "$out"
}

cfip_sample_one_cidr() {
    local cidr="$1" seed="${2:-${CFIP_SAMPLE_SEED:-0}}"
    cfip_is_ipv4 "${cidr%/*}" && cfip_sample_ipv4_cidr "$cidr" "$seed" || cfip_sample_ipv6_cidr "$cidr" "$seed"
}

cfip_pick_json_slice() {
    local json="$1" start="$2" count="$3"
    jq --argjson s "$start" --argjson c "$count" '.[$s:($s+$c)]' "$json"
}

# Schedule one family. Simple allocation:
#   12.5% local champions, 62.5% community seeds, 25% CIDR exploration.
# Missing quota automatically flows to the remaining pools. Community consensus is preferred;
# the tail rotates between runs so a large community pool is explored over time.
cfip_schedule_family() {
    local family="$1" budget="$2" all_records="$3" history_file="$4" output="$5"
    local hq oq cq community_target history_actual run_offset=0 hist community ranges selected tmp count deficit topq tailq clen
    hq=$((budget/8)); oq=$((budget/4)); cq=$((budget-hq-oq)); community_target=$cq
    ((budget>0)) || { printf '[]' | cfip_atomic_write "$output"; return 0; }
    [[ -s "${CFIP_RUN_HISTORY:-}" ]] && run_offset="$(wc -l <"$CFIP_RUN_HISTORY" 2>/dev/null || printf 0)"
    hist="$(mktemp "${TMPDIR:-/tmp}/cfip-hist.XXXXXX")"; community="$(mktemp "${TMPDIR:-/tmp}/cfip-community.XXXXXX")"; ranges="$(mktemp "${TMPDIR:-/tmp}/cfip-ranges.XXXXXX")"; selected="$(mktemp "${TMPDIR:-/tmp}/cfip-selected.XXXXXX")"
    jq --arg f "$family" '[.[]|select(.family==$f)]' "$history_file" >"$hist"
    jq --arg f "$family" '[.[]|select(.kind=="ip" and .family==$f and .sourceClass!="official")]
      | group_by(.value)
      | map({ip:.[0].value,family:.[0].family,origin:"community",sources:(map(.sourceId)|unique),sourceClass:(map(.sourceClass)|unique|join(",")),sourceCount:(map(.sourceId)|unique|length),stale:(all(.stale==true))})
      | sort_by(.stale,-.sourceCount,.ip)' "$all_records" >"$community"
    jq --arg f "$family" '[.[]|select(.kind=="cidr" and .family==$f)] | unique_by(.value)' "$all_records" >"$ranges"
    printf '[]' >"$selected"

    # Champions first.
    jq --argjson n "$hq" '[.[:$n][] | {ip,family,origin:"history",sources:["local-history"],sourceClass:"history",sourceCount:0,stale:false}]' "$hist" >"$selected"
    history_actual="$(jq 'length' "$selected")"; community_target=$((cq + hq - history_actual))

    # Community: 2/3 strongest consensus, 1/3 rotating tail. Unused history quota flows here first.
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-cpick.XXXXXX")"; topq=$((community_target*2/3)); tailq=$((community_target-topq)); clen="$(jq 'length' "$community")"
    jq --argjson n "$topq" --slurpfile s "$selected" '[.[] | select(.ip as $ip | ($s[0]|map(.ip)|index($ip)|not))][:$n]' "$community" >"$tmp.top"
    jq --slurpfile top "$tmp.top" --slurpfile s "$selected" '[.[] | select(.ip as $ip | (($top[0]+$s[0])|map(.ip)|index($ip)|not))]' "$community" >"$tmp.rest"
    local restlen start
    restlen="$(jq 'length' "$tmp.rest")"; start=0; ((restlen>0)) && start=$((run_offset % restlen))
    if ((restlen>0 && tailq>0)); then
        jq --argjson start "$start" --argjson n "$tailq" '(.[$start:] + .[:$start])[:$n]' "$tmp.rest" >"$tmp.tail"
    else printf '[]' >"$tmp.tail"; fi
    jq -s 'add' "$selected" "$tmp.top" "$tmp.tail" >"$selected.next" && mv "$selected.next" "$selected"
    rm -f "$tmp" "$tmp.top" "$tmp.rest" "$tmp.tail"

    # CIDR exploration; sample explicit IPs and avoid selected duplicates.
    local want current rlen idx attempts=0 ip cidr max_attempts sample_seed
    current="$(jq 'length' "$selected")"; want=$((budget-current)); ((want<oq)) && want=$oq
    rlen="$(jq 'length' "$ranges")"; max_attempts=$((want*20+100)); idx=0
    while ((rlen>0 && $(jq 'length' "$selected") < budget && attempts < max_attempts)); do
        cidr="$(jq -r --argjson i "$((idx%rlen))" '.[$i].value' "$ranges")"; idx=$((idx+1)); attempts=$((attempts+1))
        sample_seed="${CFIP_SAMPLE_SEED:-$run_offset}:$idx:$attempts"
        ip="$(cfip_sample_one_cidr "$cidr" "$sample_seed" 2>/dev/null || true)"; [[ -n "$ip" ]] || continue
        # A public CIDR base does not imply every sampled address is public.
        cfip_is_public_candidate "$ip" || continue
        jq -e --arg ip "$ip" 'map(.ip)|index($ip)!=null' "$selected" >/dev/null && continue
        jq --arg ip "$ip" --arg family "$family" --arg cidr "$cidr" --arg class "$(jq -r --arg cidr "$cidr" 'first(.[]|select(.kind=="cidr" and .value==$cidr)|.sourceClass) // "unknown"' "$all_records")" '. + [{ip:$ip,family:$family,origin:"range-explore",sources:["cidr:"+$cidr],sourceClass:$class,sourceCount:0,stale:false}]' "$selected" >"$selected.next" && mv "$selected.next" "$selected"
    done

    # If ranges could not fill the target, consume all remaining community/history candidates.
    count="$(jq 'length' "$selected")"; deficit=$((budget-count))
    if ((deficit>0)); then
        jq --slurpfile s "$selected" '[.[] | select(.ip as $ip | ($s[0]|map(.ip)|index($ip)|not))]' "$community" >"$community.left"
        jq --argjson n "$deficit" --slurpfile s "$selected" '$s[0] + .[:$n]' "$community.left" >"$selected.next" && mv "$selected.next" "$selected"
        rm -f "$community.left"
    fi
    count="$(jq 'length' "$selected")"; deficit=$((budget-count))
    if ((deficit>0)); then
        jq --arg f "$family" --slurpfile s "$selected" '[.[] | select(.family==$f) | {ip,family,origin:"history",sources:["local-history"],sourceClass:"history",sourceCount:0,stale:false} | select(.ip as $ip | ($s[0]|map(.ip)|index($ip)|not))]' "$history_file" >"$hist.left"
        jq --argjson n "$deficit" --slurpfile s "$selected" '$s[0] + .[:$n]' "$hist.left" >"$selected.next" && mv "$selected.next" "$selected"
        rm -f "$hist.left"
    fi
    jq --argjson n "$budget" '(reduce .[] as $x ([]; if any(.[]; .ip==$x.ip) then . else .+[$x] end))[:$n]' "$selected" | cfip_atomic_write "$output"
    rm -f "$hist" "$community" "$ranges" "$selected"
}

cfip_add_local_cfst_range_fallbacks() {
    local all_records="$1" ids="${CFIP_BUILTIN_SOURCES:-}" fam id file parsed tmp
    for fam in ipv4 ipv6; do
        [[ "${CFIP_IP_TYPE:-ipv4}" == "$fam" || "${CFIP_IP_TYPE:-ipv4}" == both ]] || continue
        [[ "$fam" == ipv4 ]] && id=cloudflare-official-v4 || id=cloudflare-official-v6
        [[ " $ids " == *" $id "* ]] || continue
        if jq -e --arg f "$fam" 'any(.[]; .kind=="cidr" and .family==$f and .sourceClass=="official")' "$all_records" >/dev/null 2>&1; then continue; fi
        [[ "$fam" == ipv4 ]] && file="${CFIP_WORK_DIR:-/usr/bin}/cfst/ip.txt" || file="${CFIP_WORK_DIR:-/usr/bin}/cfst/ipv6.txt"
        [[ -s "$file" ]] || continue
        parsed="$(mktemp "${TMPDIR:-/tmp}/cfip-local-range.XXXXXX")"; tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-local-records.XXXXXX")"
        cfip_parse_source_file "$file" cidr "cfst-local-$fam" official "$fam" true "$parsed" || { rm -f "$parsed" "$tmp"; continue; }
        jq '.records' "$parsed" >"$tmp"
        jq -s '.[0]+.[1]' "$all_records" "$tmp" >"$all_records.next" && mv "$all_records.next" "$all_records"
        rm -f "$parsed" "$tmp"
    done
}

cfip_prepare_candidate_pool() {
    local pool_output="$1" input_output="$2" source_status_output="$3" all_records history v4 v6 budget="${CFIP_CANDIDATE_BUDGET:-128}" v4budget=0 v6budget=0 v4count=0 v6count=0 deficit
    all_records="$(mktemp "${TMPDIR:-/tmp}/cfip-records.XXXXXX")"; history="$(mktemp "${TMPDIR:-/tmp}/cfip-history.XXXXXX")"; v4="$(mktemp "${TMPDIR:-/tmp}/cfip-v4.XXXXXX")"; v6="$(mktemp "${TMPDIR:-/tmp}/cfip-v6.XXXXXX")"
    cfip_collect_enabled_sources "$all_records" "$source_status_output"
    cfip_add_local_cfst_range_fallbacks "$all_records"
    cfip_history_pool_json "$history"
    case "${CFIP_IP_TYPE:-ipv4}" in
      ipv4) v4budget=$budget ;;
      ipv6) v6budget=$budget ;;
      both) v6budget=$((budget/4)); v4budget=$((budget-v6budget)) ;;
    esac
    cfip_schedule_family ipv4 "$v4budget" "$all_records" "$history" "$v4"
    cfip_schedule_family ipv6 "$v6budget" "$all_records" "$history" "$v6"
    v4count="$(jq 'length' "$v4")"; v6count="$(jq 'length' "$v6")"
    if [[ "${CFIP_IP_TYPE:-ipv4}" == both ]]; then
        deficit=$((budget-v4count-v6count))
        if ((deficit>0 && v6count<v6budget)); then cfip_schedule_family ipv4 "$((v4budget+deficit))" "$all_records" "$history" "$v4"; fi
        v4count="$(jq 'length' "$v4")"; v6count="$(jq 'length' "$v6")"; deficit=$((budget-v4count-v6count))
        if ((deficit>0)); then cfip_schedule_family ipv6 "$((v6budget+deficit))" "$all_records" "$history" "$v6"; fi
    fi
    jq -s --argjson budget "$budget" '(.[0]+.[1]) | reduce .[] as $x ([]; if any(.[]; .ip==$x.ip) then . else .+[$x] end) | .[:$budget]' "$v4" "$v6" | cfip_atomic_write "$pool_output"
    : >"$input_output"
    while IFS=$'\t' read -r ip family; do
        [[ "$family" == ipv6 ]] && printf '%s/128\n' "$ip" >>"$input_output" || printf '%s/32\n' "$ip" >>"$input_output"
    done < <(jq -r '.[]|[.ip,.family]|@tsv' "$pool_output")
    rm -f "$all_records" "$history" "$v4" "$v6"
    [[ -s "$input_output" ]]
}

cfip_source_status_json() {
    local f="${CFIP_SOURCE_STATUS_FILE:-${CFIP_RUNTIME_DIR:-/tmp/cf_ip}/source-status.json}"
    [[ -s "$f" ]] && cat "$f" || printf '[]'
}
