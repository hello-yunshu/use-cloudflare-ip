#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
export CFIP_STATUS_DIR="$tmp"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
printf '%s\n' '[{"ip":"192.0.2.1","family":"ipv4","cfstRank":2,"sourceReliability":0.7},{"ip":"192.0.2.2","family":"ipv4","cfstRank":1,"sourceReliability":0.4},{"ip":"2001:db8::1","family":"ipv6","cfstRank":3,"previousWinner":true}]' >"$tmp/input.json"
cfip_adaptive_orders_json "$tmp/input.json" >"$tmp/one.json"
cfip_adaptive_orders_json "$tmp/input.json" >"$tmp/two.json"
cmp "$tmp/one.json" "$tmp/two.json"
test "$(jq -r '.adaptiveOrder|length' "$tmp/one.json")" = 3
echo 'Adaptive scheduler deterministic contract passed'
