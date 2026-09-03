#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/rill-evidence.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
printf '%s\n' '{broken' >"$CFIP_RILL_EVIDENCE_FILE"
test "$(cfip_rill_evidence_json)" = '[]'
test -n "$(find "$TMP" -name 'rill-evidence.json.quarantine.*' -type f -print -quit)"
echo 'Corrupt evidence is quarantined fail-closed'
