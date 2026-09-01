#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_SOURCE_POLICY=community-heavy CFIP_SOURCE_POLICY_FILE="$TMP/source-policy.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
ordered="$(cfip_source_policy_order 'cloudflare-official-v4 lancelotrar-best-cf-ipv4 dustinwin-bestcf-cmcc')"
test "$ordered" = 'lancelotrar-best-cf-ipv4 dustinwin-bestcf-cmcc cloudflare-official-v4'
printf '%s\n' '{"candidateOutcome":"success","reward":0.8}' >"$TMP/outcome.json"
cfip_source_policy_record "$TMP/outcome.json"
jq -e '.selected=="community-heavy" and .policies."community-heavy".samples==1 and .policies."community-heavy".ewmaReward==0.8' "$CFIP_SOURCE_POLICY_FILE" >/dev/null
echo 'Stable source policy registry and bounded feedback contract passed'
