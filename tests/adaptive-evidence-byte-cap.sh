#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export CFIP_STATUS_DIR="$tmp" CFIP_ADAPTIVE_EVIDENCE_MAX_BYTES=1200
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
pad="$(printf '%080d' 0 | tr 0 x)"
jq -n --arg pad "$pad" '[range(1;12)|{seq:.,padding:$pad}]' >"$tmp/evidence.json"
cfip_adaptive_write_evidence "$tmp/evidence.json"
test "$(wc -c <"$CFIP_ADAPTIVE_EVIDENCE_FILE" | tr -d ' ')" -le 1200
test "$(jq '.[0].seq' "$CFIP_ADAPTIVE_EVIDENCE_FILE")" -gt 1
test "$(jq '.[-1].seq' "$CFIP_ADAPTIVE_EVIDENCE_FILE")" = 11
test "$(cfip_adaptive_evidence_json | jq 'length')" -gt 0
echo 'Adaptive evidence is bounded at write time and retains newest records'
