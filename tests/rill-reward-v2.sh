#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_LOG_FILE="$TMP/log"
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

cat >"$TMP/good.json" <<'JSON'
{"candidateOutcome":"success","delayedStability":0.9,"probes":[
  {"domain":"one.example","success":true,"totalMs":40,"ttfbMs":20,"lossRate":0.0,"downloadMBps":80},
  {"domain":"two.example","success":true,"totalMs":70,"ttfbMs":30,"lossRate":0.0,"downloadMBps":80}]}
JSON
cat >"$TMP/worst-domain.json" <<'JSON'
{"candidateOutcome":"success","delayedStability":0.9,"probes":[
  {"domain":"one.example","success":true,"totalMs":40,"ttfbMs":20,"lossRate":0.0,"downloadMBps":80},
  {"domain":"two.example","success":true,"totalMs":9000,"ttfbMs":9000,"lossRate":0.8,"downloadMBps":80}]}
JSON
cat >"$TMP/failure.json" <<'JSON'
{"candidateOutcome":"failure","probes":[{"domain":"one.example","success":false,"totalMs":10000,"ttfbMs":10000,"lossRate":1}]}
JSON
good="$(cfip_rill_reward_json "$TMP/good.json")"
worst="$(cfip_rill_reward_json "$TMP/worst-domain.json")"
test "$(jq -r '.rewardVersion' <<<"$good")" = 2
test "$(jq -r '.reward' <<<"$good")" != "-1"
awk -v x="$(jq -r '.reward' <<<"$good")" 'BEGIN { exit !(x >= -1 && x <= 1) }'
awk -v good="$(jq -r '.reward' <<<"$good")" -v worst="$(jq -r '.reward' <<<"$worst")" 'BEGIN { exit !(good > worst) }'
test "$(cfip_rill_reward_from_outcome "$TMP/failure.json")" = -1
echo 'Rill Reward v2 multi-domain contract passed'
