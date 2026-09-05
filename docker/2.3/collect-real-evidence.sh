#!/usr/bin/env bash
set -Eeuo pipefail

OUTPUT="${1:?output JSON is required}"
MAX_PROBES="${CFIP_REAL_MAX_PROBES:-4}"
MAX_TIME="${CFIP_REAL_TOTAL_TIMEOUT_SECONDS:-20}"
TARGETS="${CFIP_REAL_TARGETS:-https://www.cloudflare.com/cdn-cgi/trace https://one.one.one.one/cdn-cgi/trace}"
[[ "$MAX_PROBES" =~ ^[1-9][0-9]*$ && "$MAX_PROBES" -le 8 ]]
[[ "$MAX_TIME" =~ ^[1-9][0-9]*$ && "$MAX_TIME" -le 60 ]]
mkdir -p "$(dirname "$OUTPUT")"
started="$(date +%s)"; results='[]'; count=0
for target in $TARGETS; do
    ((count < MAX_PROBES)) || break
    now="$(date +%s)"; ((now-started < MAX_TIME)) || break
    remaining=$((MAX_TIME-(now-started))); curl_timeout=5; ((remaining < curl_timeout)) && curl_timeout="$remaining"
    ((curl_timeout > 0)) || break
    probe_started="$(date +%s)"
    http_code='000'; rc=0
    http_code="$(curl --silent --show-error --location --max-time "$curl_timeout" --output /dev/null --write-out '%{http_code}' "$target")" || rc=$?
    [[ "$http_code" =~ ^[0-9]{3}$ ]] || http_code=000
    probe_finished="$(date +%s)"
    duration=$(((probe_finished-probe_started)*1000)); ((duration < 0)) && duration=0
    results="$(jq -cn --argjson old "$results" --arg target "$target" --argjson code "$http_code" --argjson duration "$duration" --argjson rc "$rc" '$old + [{target:$target,httpStatus:$code,curlExit:$rc,durationMs:$duration,measured:($rc==0 and $code >= 200 and $code < 500)}]')"
    count=$((count+1))
done
generated="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -cn --arg generatedAt "$generated" --arg hostPlatform "${HOST_PLATFORM:-unknown}" --arg dockerPlatform "${DOCKER_PLATFORM:-unknown}" --argjson maxProbes "$MAX_PROBES" --argjson maxSeconds "$MAX_TIME" --argjson results "$results" '{schemaVersion:1,kind:"cloudflare-ip-adaptive-real-evidence",generatedAt:$generatedAt,environment:"macbook-docker-real-network",timingMode:"measured",hostPlatform:$hostPlatform,dockerPlatform:$dockerPlatform,bounded:{maxProbes:$maxProbes,maxTotalSeconds:$maxSeconds},results:$results,physicalOpenwrt:"SKIPPED (user-approved)",soak:"SKIPPED (user-approved)"}' >"$OUTPUT"
printf 'real network evidence written: %s\n' "$OUTPUT"
