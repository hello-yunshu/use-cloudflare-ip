#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_HOLDOUT_INTERVAL=1 CFIP_TARGET_DOMAINS=one.example
export CFIP_RILL_RUNTIME="$TMP/runtime"; printf '%s\n' '#!/usr/bin/env bash' >"$CFIP_RILL_RUNTIME"; chmod +x "$CFIP_RILL_RUNTIME"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat >"$TMP/decision.json" <<'JSON'
{"decisionId":"holdout-no-feedback","effectiveMode":"assisted","nativeOrder":["104.16.1.1"],"authorityActionId":"104.16.1.2"}
JSON
printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"}]' >"$TMP/native.json"
printf '%s\n' '{"reward":0.8}' >"$TMP/actual.json"
cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:true,totalMs:20,ttfbMs:10}'; }
cfip_rill_holdout "$TMP/decision.json" "$TMP/native.json" "$TMP/actual.json" "$CFIP_TARGET_DOMAINS" 1 "$TMP/holdout.json"
test ! -s "$TMP/runtime.log"
test "$(jq -r '.feedbackEligible' "$TMP/holdout.json")" = false
test "$(jq -e 'has("selectedActionId")|not' "$TMP/holdout.json")" = true
echo 'Holdout never enters the Runtime feedback path'
