#!/usr/bin/env bash
# shellcheck shell=bash

cfip_csv_num() {
    local v="${1:-}"
    [[ "$v" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { printf null; return; }
    awk -v x="$v" 'BEGIN{if (x==x && x<1e308 && x>-1e308) printf "%s",x; else printf "null"}'
}

# Parse one or more CFST CSVs into CandidateObservationV1-compatible JSON.
# Backward compatible specs: /path/result.csv:ipv4|ipv6|auto. A bare path uses auto family detection.
cfip_parse_cfst() {
    local output="$1" protocol="$2" limit="$3"; shift 3
    local tmp spec file family rank=0 line ip sent received loss latency download colo actual_family meta='{}' prefix_key
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-candidates.XXXXXX")" || return 1
    printf '[]' >"$tmp"
    for spec in "$@"; do
        case "$spec" in *:ipv4|*:ipv6|*:auto) family="${spec##*:}"; file="${spec%:*}" ;; *) family=auto; file="$spec" ;; esac
        [[ -s "$file" ]] || continue
        while IFS=',' read -r ip sent received loss latency download colo _rest; do
            [[ -n "$ip" ]] || continue
            ip="${ip%$'\r'}"; ip="${ip#[}"; ip="${ip%]}"
            [[ "$ip" == IP || "$ip" == ip || "$ip" == IP地址 ]] && continue
            if [[ "$family" == auto ]]; then actual_family="$(cfip_ip_family "$ip" 2>/dev/null || true)"; [[ -n "$actual_family" ]] || continue
            else
                actual_family="$family"
                if [[ "$family" == ipv4 ]]; then cfip_is_ipv4 "$ip" || continue; else cfip_is_ipv6 "$ip" || continue; fi
            fi
            rank=$((rank+1)); ((rank <= limit)) || break 2
            local loss_json latency_json download_json sent_json received_json
            sent_json="$(cfip_csv_num "$sent")"; received_json="$(cfip_csv_num "$received")"
            loss_json="$(cfip_csv_num "$loss")"; latency_json="$(cfip_csv_num "$latency")"; download_json="$(cfip_csv_num "$download")"
            if [[ "$loss_json" != null ]] && awk -v x="$loss_json" 'BEGIN{exit !(x>1)}'; then loss_json="$(awk -v x="$loss_json" 'BEGIN{printf "%.8g",x/100}')"; fi
            meta='{}'
            if [[ -n "${CFIP_INPUT_POOL_FILE:-}" && -s "${CFIP_INPUT_POOL_FILE:-}" ]]; then
                meta="$(jq -c --arg ip "$ip" 'first(.[]|select(.ip==$ip)) // {}' "$CFIP_INPUT_POOL_FILE" 2>/dev/null || printf '{}')"
            fi
            prefix_key="$(cfip_prefix_key "$ip" 2>/dev/null || true)"
            jq -c --arg ip "$ip" --arg family "$actual_family" --arg protocol "$protocol" --arg colo "${colo%$'\r'}" \
                --arg prefixKey "$prefix_key" --argjson rank "$rank" --argjson sent "$sent_json" --argjson received "$received_json" \
                --argjson loss "$loss_json" --argjson latency "$latency_json" --argjson download "$download_json" --argjson meta "$meta" \
                '. + [{schemaVersion:1,candidateId:("cfst:"+$ip),ip:$ip,family:$family,cfstRank:$rank,
                       sent:$sent,received:$received,lossRate:$loss,avgLatencyMs:$latency,downloadMBps:$download,
                       colo:(if ($colo|gsub("^[[:space:]]+|[[:space:]]+$";""))=="" then null else ($colo|gsub("^[[:space:]]+|[[:space:]]+$";"")) end),prefixKey:(if $prefixKey=="" then null else $prefixKey end),testProtocol:$protocol,
                       origin:($meta.origin//"unknown"),sources:($meta.sources//[]),sourceCount:($meta.sourceCount//0),sourceStale:($meta.stale//false)}]' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp"
        done <"$file"
    done
    cat "$tmp" | cfip_atomic_write "$output"
    rm -f "$tmp"
}

cfip_probe_one() {
    local ip="$1" domain="$2" family="$3" timeout_s="${4:-5}" resolve_ip="$ip" proto rc=0 raw remaining
    remaining="$(cfip_deadline_remaining 2>/dev/null || printf 86400)"
    ((remaining>0)) || { jq -cn --arg ip "$ip" --arg domain "$domain" --arg family "$family" '{schemaVersion:1,ip:$ip,domain:$domain,family:$family,success:false,errorClass:"measurement_budget",curlExit:124,httpCode:0,connectMs:0,tlsMs:0,ttfbMs:0,totalMs:0}'; return 0; }
    ((timeout_s>remaining)) && timeout_s="$remaining"
    [[ "$family" == ipv6 ]] && resolve_ip="[$ip]"
    [[ "$family" == ipv6 ]] && proto=-6 || proto=-4
    raw="$(curl -sS "$proto" --connect-timeout "$timeout_s" --max-time "$timeout_s" \
        --resolve "${domain}:443:${resolve_ip}" "https://${domain}/" -o /dev/null \
        -w '%{http_code},%{time_connect},%{time_appconnect},%{time_starttransfer},%{time_total}' 2>/dev/null)" || rc=$?
    local code=0 connect=0 tls=0 ttfb=0 total=0 success=false err=none
    if [[ -n "$raw" ]]; then IFS=',' read -r code connect tls ttfb total <<<"$raw"; fi
    if ((rc == 0)) && [[ "$code" =~ ^[0-9]+$ ]] && ((code >= 200 && code < 500)); then success=true; else
        case "$rc" in 6) err=dns ;; 7) err=connect ;; 28) err=timeout ;; 35|51|60) err=tls ;; 124) err=measurement_budget ;; *) err=http_or_transport ;; esac
    fi
    jq -cn --arg ip "$ip" --arg domain "$domain" --arg family "$family" --arg err "$err" \
      --argjson success "$success" --argjson rc "$rc" --argjson code "${code:-0}" \
      --argjson connect "$(awk -v x="${connect:-0}" 'BEGIN{printf "%.3f",x*1000}')" \
      --argjson tls "$(awk -v x="${tls:-0}" 'BEGIN{printf "%.3f",x*1000}')" \
      --argjson ttfb "$(awk -v x="${ttfb:-0}" 'BEGIN{printf "%.3f",x*1000}')" \
      --argjson total "$(awk -v x="${total:-0}" 'BEGIN{printf "%.3f",x*1000}')" \
      '{schemaVersion:1,ip:$ip,domain:$domain,family:$family,success:$success,errorClass:$err,curlExit:$rc,httpCode:$code,
        connectMs:$connect,tlsMs:$tls,ttfbMs:$ttfb,totalMs:$total}'
}

cfip_probe_candidate_record() {
    local candidate="$1" domains_csv="$2" timeout_s="$3" output="$4" ip family probes='[]' p all_ok=true domain summary
    ip="$(jq -r '.ip' <<<"$candidate")"; family="$(jq -r '.family' <<<"$candidate")"
    IFS=',' read -r -a domains <<<"$domains_csv"
    for domain in "${domains[@]}"; do
        p="$(cfip_probe_one "$ip" "$domain" "$family" "$timeout_s")"
        probes="$(jq -cn --argjson a "$probes" --argjson p "$p" '$a+[$p]')"
        [[ "$(jq -r '.success' <<<"$p")" == true ]] || all_ok=false
    done
    summary="$(jq -cn --argjson p "$probes" '($p|map(select(.success==true))) as $s |
      {successCount:($s|length),probeCount:($p|length),
       connectMs:(if ($s|length)>0 then ($s|map(.connectMs)|add/length) else null end),
       tlsMs:(if ($s|length)>0 then ($s|map(.tlsMs)|add/length) else null end),
       ttfbMs:(if ($s|length)>0 then ($s|map(.ttfbMs)|add/length) else null end),
       totalMs:(if ($s|length)>0 then ($s|map(.totalMs)|add/length) else null end)}')"
    jq -cn --argjson c "$candidate" --argjson probes "$probes" --argjson summary "$summary" --argjson eligible "$all_ok" '$c + {eligible:$eligible,probes:$probes,probeSummary:$summary}' | cfip_atomic_write "$output"
}

cfip_probe_candidates() {
    local input="$1" output="$2" domains_csv="$3" timeout_s="$4" concurrency="${CFIP_PROBE_CONCURRENCY:-4}" tmpdir idx=0 candidate pid f
    local -a pids=()
    [[ "$concurrency" =~ ^[1-9][0-9]*$ ]] || concurrency=4
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cfip-probes.XXXXXX")" || return 1
    while IFS= read -r candidate; do
        idx=$((idx+1)); cfip_probe_candidate_record "$candidate" "$domains_csv" "$timeout_s" "$tmpdir/$idx.json" & pids+=("$!")
        if ((${#pids[@]} >= concurrency)); then for pid in "${pids[@]}"; do wait "$pid" || true; done; pids=(); fi
    done < <(jq -c '.[]' "$input")
    if ((${#pids[@]})); then
        for pid in "${pids[@]}"; do wait "$pid" || true; done
    fi
    if ((idx==0)); then printf '[]' | cfip_atomic_write "$output"; rm -rf "$tmpdir"; return 0; fi
    for ((f=1;f<=idx;f++)); do [[ -s "$tmpdir/$f.json" ]] || printf '{}' >"$tmpdir/$f.json"; done
    jq -s '[.[]|select(type=="object" and has("ip"))]' "$tmpdir"/*.json | cfip_atomic_write "$output"
    rm -rf "$tmpdir"
}

cfip_probe_candidates_batched() {
    local input="$1" output="$2" domains_csv="$3" timeout_s="$4" required="${5:-1}" batch_size="${6:-4}" max_count="${7:-}" tmpdir total offset=0 take part probed_json aggregate='[]' batches=0 early=false start end remaining best_rank safe_count candidates_considered probed_count avoided
    [[ -s "$input" ]] || { printf '[]\n' | cfip_atomic_write "$output"; return 0; }
    total="$(jq 'length' "$input")"; [[ "$max_count" =~ ^[1-9][0-9]*$ ]] || max_count="$total"
    ((max_count < total)) && total="$max_count"
    [[ "$batch_size" =~ ^[1-9][0-9]*$ ]] || batch_size=4
    [[ "$required" =~ ^[1-9][0-9]*$ ]] || required=1
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/cfip-probe-batches.XXXXXX")" || return 1
    start="$(date +%s)"
    while ((offset < total)); do
        if declare -F cfip_deadline_remaining >/dev/null 2>&1; then remaining="$(cfip_deadline_remaining)"; ((remaining > 0)) || break; fi
        take="$batch_size"; ((offset+take > total)) && take=$((total-offset))
        jq --argjson start "$offset" --argjson take "$take" '.[$start:($start+$take)]' "$input" >"$tmpdir/input-$batches.json"
        probed_json="$tmpdir/probed-$batches.json"
        cfip_probe_candidates "$tmpdir/input-$batches.json" "$probed_json" "$domains_csv" "$timeout_s" || true
        aggregate="$(jq -cn --argjson all "$aggregate" --argjson next "$(cat "$probed_json" 2>/dev/null || printf '[]')" '$all+$next')"
        offset=$((offset+take)); batches=$((batches+1))
        safe_count="$(jq --argjson required "$required" '[.[]|select(.eligible==true and ((.probeSummary.lossRate // .lossRate // 0)<=0.25) and ((.probeSummary.ttfbMs // 0)<=3000) and ((.probeSummary.totalMs // 0)<=5000))]|length' <<<"$aggregate")"
        best_rank="$(jq -r '[.[]|select(.eligible==true)|(.cfstRank//999999)]|min // 999999' <<<"$aggregate")"
        if [[ "${CFIP_EARLY_STOP_ENABLED:-true}" == true ]] && ((safe_count >= required)); then
            if ((offset >= total)); then early=true
            else
                remaining="$(jq --argjson start "$offset" --argjson max "$total" '.[$start:$max]' "$input")"
                if [[ "$(jq --argjson rank "$best_rank" '[.[]|select((.cfstRank//999999)<=($rank+3))]|length' <<<"$remaining")" == 0 ]]; then early=true; fi
            fi
        fi
        [[ "$early" == true ]] && break
    done
    candidates_considered="$(jq 'length' "$input")"; probed_count="$(jq 'length' <<<"$aggregate")"; avoided=$((candidates_considered-probed_count)); end="$(date +%s)"
    printf '%s\n' "$aggregate" | cfip_atomic_write "$output"
    if [[ -n "${CFIP_PROBE_METRICS_FILE:-}" ]]; then
        jq -cn --argjson considered "$candidates_considered" --argjson probed "$probed_count" --argjson batches "$batches" --argjson avoided "$avoided" --argjson seconds "$((end-start))" --argjson early "$early" '{schemaVersion:1,candidatesConsidered:$considered,candidatesProbed:$probed,probeBatches:$batches,avoidedProbes:$avoided,totalProbeTimeSeconds:$seconds,earlyStopHit:$early}' | cfip_atomic_write "$CFIP_PROBE_METRICS_FILE"
    fi
    rm -rf "$tmpdir"
    ((probed_count > 0))
}

cfip_native_rank() {
    local input="$1" output="$2"
    jq '[.[] | select(.eligible == true)]
      | sort_by((.probeSummary.totalMs // 1e18),(.probeSummary.ttfbMs // 1e18),(.lossRate // 1e18),(.avgLatencyMs // 1e18),-(.downloadMBps // 0),.cfstRank,.ip)
      | to_entries | map(.value + {nativeRank:(.key+1)})' "$input" | cfip_atomic_write "$output"
}

cfip_post_apply_probe() {
    local selected_json="$1" domains_csv="$2" timeout_s="$3" output="$4" ip family domain probes='[]' ok=true p observed_at count=0 candidate loss throughput tmp reward_json
    [[ "$(jq 'length' "$selected_json" 2>/dev/null || printf 0)" -gt 0 ]] || return 2
    IFS=',' read -r -a domains <<<"$domains_csv"
    while IFS=$'\t' read -r ip family; do
        [[ -n "$ip" ]] || continue
        count=$((count+1))
        candidate="$(jq -c --arg ip "$ip" '.[]|select((.ip|tostring)==$ip)' "$selected_json" 2>/dev/null | head -n1)"; [[ -n "$candidate" ]] || candidate='{}'
        loss="$(jq -r '.lossRate // 1' <<<"$candidate")"; throughput="$(jq -r '.downloadMBps // 0' <<<"$candidate")"
        for domain in "${domains[@]}"; do
            p="$(cfip_probe_one "$ip" "$domain" "$family" "$timeout_s")"
            probes="$(jq -cn --argjson a "$probes" --argjson p "$p" --argjson loss "$loss" --argjson throughput "$throughput" '$a+[$p+{lossRate:$loss,downloadMBps:$throughput}]')"
            [[ "$(jq -r '.success' <<<"$p")" == true ]] || ok=false
        done
    done < <(jq -r '.[]|[.ip,.family]|@tsv' "$selected_json")
    ((count > 0)) || return 2
    observed_at="$(date +%s)"
    local primary_ip
    primary_ip="$(jq -r '.[0].ip // empty' "$selected_json")"
    tmp="$(mktemp "${TMPDIR:-/tmp}/cfip-post-apply-outcome.XXXXXX")" || return 1
    jq -cn --arg runId "$CFIP_RUN_ID" --arg ip "$primary_ip" --arg decisionActionId "${CFIP_DECISION_ACTION_ID:-$primary_ip}" --argjson success "$ok" --argjson probes "$probes" --argjson observedAt "$observed_at" '
      ($probes|map(select(.success==true))) as $s |
      ($probes|map(select(.ip==$ip))) as $primary |
      ($primary|map(select(.success==true))) as $primary_ok |
      {schemaVersion:2,runId:$runId,validated:$success,candidateOutcome:(if (($primary|length)>0 and ($primary_ok|length)==($primary|length)) then "success" else "failure" end),hostOutcome:"success",censored:false,reason:(if $success then null else "candidate_probe_failed" end),observedAt:$observedAt,probes:$probes,
       ip:$ip,appliedIps:($probes|map(.ip)|unique),
       observedIp:$ip,decisionActionId:$decisionActionId,
       primaryValidated:(($primary|length)>0 and ($primary_ok|length)==($primary|length)),
       reward:(if (($primary|length)>0 and ($primary_ok|length)==($primary|length)) then ((1/(1+((($primary_ok|map(.totalMs)|add/($primary_ok|length))/1000))) + (1/(1+((($primary_ok|map(.ttfbMs)|add/($primary_ok|length))/1000)))))/2) else -1 end) }' >"$tmp"
    if declare -F cfip_rill_reward_json >/dev/null 2>&1; then
        reward_json="$(cfip_rill_reward_json "$tmp")" || reward_json='{}'
        jq --argjson reward "$reward_json" '. + {reward:$reward.reward,rewardVersion:$reward.rewardVersion,rewardComponents:$reward.components,worstDomain:$reward.worstDomain,rillShadowReward:$reward.reward,nativeCounterfactualReward:$reward.reward,rewardDelta:0,disagreement:false}' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp"
    fi
    cat "$tmp" | cfip_atomic_write "$output"; local rc=$?; rm -f "$tmp"; [[ "$ok" == true ]] && return "$rc"; return 1
}
