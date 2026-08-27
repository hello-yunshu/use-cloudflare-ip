#!/usr/bin/env bash
# IntendedMappingV1 readback. A server IP alone is insufficient evidence.

cfip_openclash_readback_intended() {
    local selected="$1" config="$2" domains_csv="$3" suffix="$4" filter="${5:-}"
    local count ip domain network
    local -a domains=() networks=()
    [[ -s "$selected" && -s "$config" ]] || return 1
    count="$(jq 'length' "$selected" 2>/dev/null || printf 0)"
    ((count > 0)) || return 1
    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        awk -v wanted="$ip" '
            /^[[:space:]]*-[[:space:]]+name:/ { if (has_ip && has_marker) found=1; in_block=1; has_ip=0; has_marker=0 }
            in_block && index($0, "[CF-") { has_marker=1 }
            in_block && /^[[:space:]]*server:/ { line=$0; sub(/^[[:space:]]*server:[[:space:]]*/, "", line); if (line == wanted) has_ip=1 }
            END { if (has_ip && has_marker) found=1; exit(found ? 0 : 1) }
        ' "$config" || return 1
    done < <(jq -r '.[].ip' "$selected")
    IFS=',' read -r -a domains <<<"$domains_csv"
    for domain in "${domains[@]}"; do
        domain="${domain#${domain%%[![:space:]]*}}"
        domain="${domain%${domain##*[![:space:]]}}"
        [[ -n "$domain" ]] || continue
        grep -Eq "(^|[[:space:]])servername:[[:space:]]*${domain}([[:space:]]|$)|(^|[[:space:]])Host:[[:space:]]*${domain}([[:space:]]|$)" "$config" || return 1
    done
    IFS=',' read -r -a networks <<<"$filter"
    for network in "${networks[@]}"; do
        network="${network#${network%%[![:space:]]*}}"
        network="${network%${network##*[![:space:]]}}"
        [[ -z "$network" ]] || grep -Eq "(^|[[:space:]])network:[[:space:]]*${network}([[:space:]]|$)" "$config" || return 1
    done
    [[ -z "$suffix" ]] || grep -Fq '[CF-' "$config" || return 1
}
