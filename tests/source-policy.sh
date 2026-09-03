#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_SOURCE_POLICY=community-heavy
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
! declare -F cfip_source_policy_decide >/dev/null
! declare -F cfip_source_policy_record >/dev/null
! rg -n 'CFIP_RILL_SOURCE_PARTITION_KEY|source-policy-decision|source-policy-qualification' "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh" >/dev/null
sources='cloudflare-official-v4 lancelotrar-best-cf-ipv4 dustinwin-bestcf-cmcc svips-best-ips'
for policy in balanced official-heavy history-heavy diversity-heavy community-heavy; do
    first="$(CFIP_SOURCE_POLICY="$policy" CFIP_SOURCE_POLICY_EFFECTIVE="$policy" cfip_source_policy_order "$sources")"
    second="$(CFIP_SOURCE_POLICY="$policy" CFIP_SOURCE_POLICY_EFFECTIVE="$policy" cfip_source_policy_order "$sources")"
    test "$first" = "$second"
done
test "$(CFIP_SOURCE_POLICY=balanced CFIP_SOURCE_POLICY_EFFECTIVE=balanced cfip_source_policy_order "$sources")" = 'cloudflare-official-v4 lancelotrar-best-cf-ipv4 dustinwin-bestcf-cmcc svips-best-ips'
test "$(CFIP_SOURCE_POLICY=community-heavy CFIP_SOURCE_POLICY_EFFECTIVE=community-heavy cfip_source_policy_order "$sources")" = 'lancelotrar-best-cf-ipv4 dustinwin-bestcf-cmcc cloudflare-official-v4 svips-best-ips'
test "$(cfip_source_policy_json | jq -r '.deterministic')" = true
CFIP_RILL_ENABLED=true CFIP_RILL_MODE=assisted CFIP_RILL_RUNTIME="$TMP/nonexistent-runtime" CFIP_SOURCE_POLICY_DECISION_FILE="$TMP/source-policy-decision.json" cfip_source_policy_json >/dev/null
test ! -e "$TMP/source-policy-decision.json"
echo 'Deterministic source policy profiles passed'
