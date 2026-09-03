#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_HISTORY_FILE="$TMP/history.json" CFIP_RILL_PREFIX_HISTORY_FILE="$TMP/prefix.json" CFIP_RILL_COLO_HISTORY_FILE="$TMP/colo.json" CFIP_TARGET_DOMAINS='one.example' CFIP_SPEEDTEST_PROTOCOL=tcp CFIP_IP_TYPE=ipv4 CFIP_SPEEDTEST_CFCOLO=''
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cfip_rill_context_guard; old="$(cfip_rill_context_fingerprint)"
printf '%s\n' '{"formatVersion":1,"partitions":[]}' > "$CFIP_RILL_STATE"; printf '%s\n' '{}' > "$CFIP_RILL_QUALIFICATION_FILE"; printf '%s\n' '{}' > "$CFIP_RILL_HISTORY_FILE"; printf '%s\n' '{}' > "$CFIP_RILL_PREFIX_HISTORY_FILE"; printf '%s\n' '{"entries":{}}' > "$CFIP_RILL_COLO_HISTORY_FILE"
CFIP_TARGET_DOMAINS='two.example'; cfip_rill_context_guard; new="$(cfip_rill_context_fingerprint)"
test "$old" != "$new"; test ! -e "$CFIP_RILL_STATE"; test ! -e "$CFIP_RILL_QUALIFICATION_FILE"; test "$(jq -r .contextChanged "$CFIP_RILL_STATE_META_FILE")" = true; test "$(jq -r .previousContextFingerprint "$CFIP_RILL_STATE_META_FILE")" = "$old"
echo 'Material learning-context change quarantines Candidate lineage and qualification'
