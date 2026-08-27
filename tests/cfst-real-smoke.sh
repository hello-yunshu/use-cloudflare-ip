#!/usr/bin/env bash
set -euo pipefail
CFST="${1:?CFST binary path required}"; INPUT="${2:?input path required}"; ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/result.csv"
test -x "$CFST"; grep -Eq '/32$' "$INPUT"; grep -Eq '/128$' "$INPUT"
timeout 45 "$CFST" -f "$INPUT" -n 4 -t 1 -dn 1 -dt 1 -tll 0 -o "$OUT"
test -s "$OUT"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
CFIP_INPUT_POOL_FILE="$TMP/pool.json"
jq -Rn '[inputs|select(length>0)|{ip:(split("/")[0]),family:(if contains(":") then "ipv6" else "ipv4" end)}]' <"$INPUT" >"$CFIP_INPUT_POOL_FILE"
cfip_parse_cfst "$TMP/parsed.json" tcp 8 "$OUT:auto"
jq -e 'type=="array"' "$TMP/parsed.json" >/dev/null
echo 'real CFST execution and CandidateObservation parse passed'
