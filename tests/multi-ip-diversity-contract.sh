#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime"
mkdir -p "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
CFIP_RILL_MODE=assisted CFIP_RILL_ENABLED=true CFIP_RILL_SAFE_TOP_K=8 CFIP_RILL_UNSEEN_CANDIDATE_CAP=1 CFIP_IP_COUNT=3
CFIP_NATIVE_FILE="$TMP/native.json"; CFIP_RILL_FILE="$TMP/rill.json"; CFIP_SELECTED_FILE="$TMP/selected.json"
cat > "$CFIP_NATIVE_FILE" <<'JSON'
[
  {"ip":"104.16.1.1","family":"ipv4","eligible":true,"lossRate":0.01,"ttfbMs":20,"totalMs":50,"sourceClass":"official"},
  {"ip":"104.17.2.2","family":"ipv4","eligible":true,"lossRate":0.01,"ttfbMs":20,"totalMs":50,"sourceClass":"official"},
  {"ip":"2606:4700::1","family":"ipv6","eligible":true,"lossRate":0.01,"ttfbMs":20,"totalMs":50,"sourceClass":"community"},
  {"ip":"104.18.3.3","family":"ipv4","eligible":true,"lossRate":0.01,"ttfbMs":20,"totalMs":50,"sourceClass":"official"}
]
JSON
cat > "$CFIP_RILL_FILE" <<'JSON'
{"candidates":[
  {"ip":"104.16.1.1","family":"ipv4","eligible":true,"rillRank":1,"sourceClass":"official"},
  {"ip":"104.17.2.2","family":"ipv4","eligible":true,"rillRank":2,"sourceClass":"official"},
  {"ip":"2606:4700::1","family":"ipv6","eligible":true,"rillRank":3,"sourceClass":"community"},
  {"ip":"104.18.3.3","family":"ipv4","eligible":true,"rillRank":4,"sourceClass":"official"}
]}
JSON
cfip_rill_qualified() { return 0; }
select_assisted_candidates
test "$(jq -r '.[0].ip' "$CFIP_SELECTED_FILE")" = 104.16.1.1
test "$(jq -r '.[1].ip' "$CFIP_SELECTED_FILE")" = 104.17.2.2
test "$(jq -r '.[2].ip' "$CFIP_SELECTED_FILE")" = 2606:4700::1
test "$(jq -r '.[0].sourceClass' "$CFIP_SELECTED_FILE")" = official
test "$(jq -r '.[2].sourceClass' "$CFIP_SELECTED_FILE")" = community
echo 'Native-safe multi-IP diversity contract passed'
