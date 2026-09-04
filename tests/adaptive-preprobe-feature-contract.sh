#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
export CFIP_STATUS_DIR="$tmp" CFIP_ADAPTIVE_SCHEDULER_VERSION=1 CFIP_ADAPTIVE_FEATURE_CONTRACT_VERSION=1
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh"
printf '%s\n' '[{"ip":"192.0.2.1","family":"ipv4","cfstRank":1,"totalMs":10,"ttfbMs":2,"success":true,"eligible":true,"probes":[{"totalMs":10}]}]' >"$tmp/input.json"
orders="$(cfip_adaptive_orders_json "$tmp/input.json")"
test "$(jq -r '.candidates[0]|has("probes")' <<<"$orders")" = false
test "$(jq -r '.candidates[0]|has("success")' <<<"$orders")" = false
test "$(jq -r '.candidates[0]|has("eligible")' <<<"$orders")" = false
test "$(jq -r '.forbiddenFields|index("probes")' <<<"$(cfip_adaptive_contract_json)")" = 0
echo 'Adaptive pre-probe feature contract passed'
