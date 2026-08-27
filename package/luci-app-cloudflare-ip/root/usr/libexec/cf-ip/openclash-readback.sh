#!/usr/bin/env bash
# OpenClash IntendedMappingV1 readback. A server IP alone is insufficient
# evidence: every expected proxy block is compared as one complete record.

cfip_openclash_mapping_tsv() {
    local config="$1"
    awk '
      function trim(v) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(/^["'"'"']|["'"'"']$/, "", v); return v }
      function emit() { if (name != "") printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", name,type,server,tls,network,servername,host }
      /^[[:space:]]*-[[:space:]]+name:[[:space:]]*/ {
        emit(); line=$0; sub(/^[[:space:]]*-[[:space:]]+name:[[:space:]]*/, "", line)
        name=trim(line); type=""; server=""; tls=""; network=""; servername=""; host=""; next
      }
      name != "" && /^[[:space:]]+type:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+type:[[:space:]]*/, "", line); type=trim(line); next }
      name != "" && /^[[:space:]]+server:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+server:[[:space:]]*/, "", line); server=trim(line); next }
      name != "" && /^[[:space:]]+tls:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+tls:[[:space:]]*/, "", line); tls=trim(line); next }
      name != "" && /^[[:space:]]+network:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+network:[[:space:]]*/, "", line); network=trim(line); next }
      name != "" && /^[[:space:]]+servername:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+servername:[[:space:]]*/, "", line); servername=trim(line); next }
      name != "" && /^[[:space:]]+Host:[[:space:]]*/ { line=$0; sub(/^[[:space:]]+Host:[[:space:]]*/, "", line); host=trim(line); next }
      END { emit() }
    ' "$config"
}

cfip_openclash_actual_mapping() {
    local config="$1" output="$2" tmp row name type server tls network servername host
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-actual.XXXXXX")" || return 1
    printf '[]' >"$tmp"
    while IFS=$'\t' read -r name type server tls network servername host; do
        [[ -n "$name" ]] || continue
        jq -cn --arg name "$name" --arg type "$type" --arg server "$server" --arg tls "$tls" \
          --arg network "$network" --arg servername "$servername" --arg host "$host" \
          '{name:$name,type:$type,server:$server,tls:$tls,network:$network,servername:(if $servername=="" then null else $servername end),host:(if $host=="" then null else $host end)}' \
          >"$tmp.row"
        jq --argjson row "$(cat "$tmp.row")" '. + [$row]' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp" || { rm -f "$tmp" "$tmp.row"; return 1; }
    done < <(cfip_openclash_mapping_tsv "$config")
    mv "$tmp" "$output"
    rm -f "$tmp.row"
}

cfip_openclash_intended_from_templates() {
    local selected="$1" config="$2" domains_csv="$3" suffix="$4" filter="$5" output="$6"
    local count name type server tls network servername host domain base seq ip idx line tmp
    local -a domains=() ips=()
    IFS=',' read -r -a domains <<<"$domains_csv"
    while IFS= read -r ip; do [[ -n "$ip" ]] && ips+=("$ip"); done < <(jq -r '.[].ip' "$selected")
    ((${#ips[@]} > 0)) || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-intended.XXXXXX")" || return 1
    printf '[]' >"$tmp"
    while IFS=$'\t' read -r name type server tls network servername host; do
        [[ -n "$name" ]] || continue
        [[ "$type" == vless || "$type" == vmess || "$type" == trojan ]] || continue
        [[ "${tls,,}" == true ]] || continue
        case "${network,,}" in ws|xhttp|grpc|h2|http) ;; *) continue ;; esac
        if [[ -n "$filter" && ",${filter}," != *",${network,,},"* ]]; then continue; fi
        domain=""
        for line in "${domains[@]}"; do
            line="${line#${line%%[![:space:]]*}}"; line="${line%${line##*[![:space:]]}}"
            if [[ "$server" == "$line" || "$servername" == "$line" || "$host" == "$line" ]]; then domain="$line"; break; fi
        done
        [[ -n "$domain" ]] || continue
        base="$name"
        while [[ "$base" =~ ^(.*)[[:space:]]\[CF-[0-9]+\][^[:space:]]*$ ]]; do base="${BASH_REMATCH[1]}"; done
        count=1; [[ -n "$suffix" ]] && count="${#ips[@]}"
        for ((idx=0; idx<count; idx++)); do
            seq=$((idx+1)); ip="${ips[$idx]}"; line="$suffix"; line="${line//\{n\}/$seq}"; line="${line//\{ip\}/$ip}"
            name="$base$line"
            jq -cn --arg name "$name" --arg server "$ip" --arg servername "$domain" --arg network "${network,,}" \
              --argjson hostRequired "$([[ "${network,,}" == ws || "${network,,}" == xhttp ]] && printf true || printf false)" \
              '{name:$name,server:$server,servername:$servername,network:$network,host:(if $hostRequired then $servername else null end)}' \
              >"$tmp.row"
            jq --argjson row "$(cat "$tmp.row")" '. + [$row]' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp" || { rm -f "$tmp" "$tmp.row"; return 1; }
        done
    done < <(cfip_openclash_mapping_tsv "$config")
    mv "$tmp" "$output"
    rm -f "$tmp.row"
}

cfip_openclash_validate_mapping() {
    local intended="$1" actual="$2"
    jq -e --slurpfile expected "$intended" --slurpfile observed "$actual" '
      ($expected[0]) as $e | ($observed[0] | map(select(.name|contains("[CF-")))) as $a |
      ($e|length)>0 and ($a|length)==($e|length) and
      (($a | map([.name,.server,.servername,.network,.host] | join("\u0000")) | unique | length) == ($a|length)) and
      all($e[]; . as $wanted | any($a[]; .name==$wanted.name and .server==$wanted.server and .servername==$wanted.servername and .network==$wanted.network and .host==$wanted.host))
    ' >/dev/null
}

cfip_openclash_readback_intended() {
    local selected="$1" config="$2" domains_csv="$3" suffix="$4" filter="${5:-}"
    local actual intended rc ip
    [[ -s "$selected" && -s "$config" ]] || return 1
    actual="$(mktemp "${TMPDIR:-/tmp}/cfip-openclash-readback.XXXXXX")" || return 1
    cfip_openclash_actual_mapping "$config" "$actual" || { rm -f "$actual"; return 1; }
    intended="${CFIP_TXN_DIR:+$CFIP_TXN_DIR/openclash-intended.json}"
    if [[ -s "$intended" ]]; then
        cfip_openclash_validate_mapping "$intended" "$actual"; rc=$?
        rm -f "$actual"
        return "$rc"
    fi
    # Compatibility fallback for callers outside a host transaction: require
    # each selected IP to belong to one marked block and validate fields in it.
    while IFS= read -r ip; do
        awk -v wanted="$ip" -v domains="$domains_csv" -v filter="$filter" '
          function ok_domain(v, n,a) { n=split(domains,a,","); for(i=1;i<=n;i++){gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i]); if(v==a[i]) return 1} return 0 }
          function emit(){ if(in_block && server==wanted && index(name,"[CF-") && (servername!="" || host!="") && ok_domain(servername!=""?servername:host) && (filter=="" || ("," filter ",") ~ "," network ",")) found=1 }
          /^[[:space:]]*-[[:space:]]+name:/ { emit(); in_block=1; name=$0; sub(/^.*name:[[:space:]]*/,"",name); server=""; servername=""; host=""; network=""; next }
          in_block && /^[[:space:]]+server:/ { server=$0; sub(/^.*server:[[:space:]]*/,"",server); next }
          in_block && /^[[:space:]]+servername:/ { servername=$0; sub(/^.*servername:[[:space:]]*/,"",servername); next }
          in_block && /^[[:space:]]+Host:/ { host=$0; sub(/^.*Host:[[:space:]]*/,"",host); next }
          in_block && /^[[:space:]]+network:/ { network=$0; sub(/^.*network:[[:space:]]*/,"",network); next }
          END { emit(); exit(found ? 0 : 1) }
        ' "$config" || { rm -f "$actual"; return 1; }
    done < <(jq -r '.[].ip' "$selected")
    rm -f "$actual"
}
