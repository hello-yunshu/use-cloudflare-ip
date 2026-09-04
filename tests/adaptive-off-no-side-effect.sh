#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export CFIP_STATUS_DIR="$tmp" CFIP_IP_COUNT=1 CFIP_IP_TYPE=ipv4
export CFIP_ADAPTIVE_MEASUREMENT_ENABLED=false CFIP_ADAPTIVE_MEASUREMENT_MODE=off
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
printf '%s\n' '[{"ip":"192.0.2.1","family":"ipv4","cfstRank":1}]' >"$tmp/input.json"
test "$(cfip_adaptive_effective_mode)" = off
cfip_adaptive_prepare_probe_input "$tmp/input.json" "$tmp/output.json" "$tmp/plan.json"
cmp "$tmp/input.json" "$tmp/output.json"
test ! -e "$CFIP_ADAPTIVE_STATE_FILE"
test ! -e "$CFIP_ADAPTIVE_EVIDENCE_FILE"
echo 'Adaptive off mode has no audit or measurement side effect'
