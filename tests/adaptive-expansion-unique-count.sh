#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export CFIP_STATUS_DIR="$tmp"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
cat >"$tmp/duplicates.json" <<'EOF_JSON'
[
  {"ip":"192.0.2.1","eligible":true,"lossRate":0,"probeSummary":{"totalMs":10,"ttfbMs":5}},
  {"ip":"192.0.2.1","eligible":true,"lossRate":0,"probeSummary":{"totalMs":11,"ttfbMs":5}},
  {"ip":"192.0.2.2","eligible":true,"lossRate":0,"probeSummary":{"totalMs":12,"ttfbMs":5}}
]
EOF_JSON
test "$(cfip_adaptive_safe_count <"$tmp/duplicates.json")" = 2
test "$(cfip_adaptive_unique_json <"$tmp/duplicates.json" | jq '[.[].ip]|unique|length')" = 2
echo 'Adaptive safe and selected counts are unique by IP'
