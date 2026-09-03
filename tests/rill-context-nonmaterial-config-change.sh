#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_TARGET_DOMAINS='one.example' CFIP_SPEEDTEST_PROTOCOL=tcp CFIP_IP_TYPE=ipv4 CFIP_SPEEDTEST_CFCOLO=''
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cfip_rill_context_guard; fp="$(cfip_rill_context_fingerprint)"; printf '%s\n' '{}' > "$CFIP_RILL_HISTORY_FILE"
CFIP_CRON_INTERVAL=15m CFIP_VERBOSE=true CFIP_SOURCE_POLICY=community-heavy CFIP_PUBLISH_ENABLED=true; cfip_rill_context_guard
test "$(jq -r .contextFingerprint "$CFIP_RILL_STATE_META_FILE")" = "$fp"; test -e "$CFIP_RILL_HISTORY_FILE"; test "$(jq -r .contextChanged "$CFIP_RILL_STATE_META_FILE")" = false
echo 'Non-material scheduler, logging, source-policy, and publisher changes retain Candidate context'
