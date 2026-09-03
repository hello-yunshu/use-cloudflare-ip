#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_TARGET_DOMAINS=' B.example, a.example, A.example ' CFIP_SPEEDTEST_PROTOCOL=TCP CFIP_IP_TYPE=IPv4 CFIP_SPEEDTEST_CFCOLO=' SJC '
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
one="$(cfip_rill_context_json)"; fp1="$(cfip_rill_context_fingerprint)"
CFIP_TARGET_DOMAINS='a.example,b.example' CFIP_SPEEDTEST_PROTOCOL=tcp CFIP_IP_TYPE=ipv4 CFIP_SPEEDTEST_CFCOLO=sjc
two="$(cfip_rill_context_json)"; fp2="$(cfip_rill_context_fingerprint)"
test "$one" = "$two"; test "$fp1" = "$fp2"
CFIP_TARGET_DOMAINS='c.example,b.example'; test "$(cfip_rill_context_fingerprint)" != "$fp1"
echo 'Learning context fingerprint normalization and material-change detection passed'
