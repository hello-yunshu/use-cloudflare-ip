#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
export CFIP_STATUS_DIR="$tmp" CFIP_IP_COUNT=1 CFIP_IP_TYPE=ipv4 CFIP_ADAPTIVE_MEASUREMENT_ENABLED=true CFIP_ADAPTIVE_MEASUREMENT_MODE=shadow CFIP_ADAPTIVE_TARGET_RATIO_PERCENT=25 CFIP_ADAPTIVE_MIN_PROBE_COUNT=1 CFIP_ADAPTIVE_MAX_PROBE_COUNT=4 CFIP_ADAPTIVE_EXPANSION_BATCH_SIZE=1
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
printf '%s\n' '[{"ip":"192.0.2.1","family":"ipv4","cfstRank":1},{"ip":"192.0.2.2","family":"ipv4","cfstRank":2}]' >"$tmp/input.json"
cp "$tmp/input.json" "$tmp/baseline.json"
cfip_adaptive_prepare_probe_input "$tmp/input.json" "$tmp/shadow.json" "$tmp/plan.json"
cmp "$tmp/baseline.json" "$tmp/shadow.json"
test "$(cfip_adaptive_effective_mode)" = shadow
echo 'Adaptive Shadow no-production-influence contract passed'
