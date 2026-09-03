#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_HOLDOUT_INTERVAL=1 CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat >"$TMP/decision.json" <<'JSON'
{"decisionId":"holdout-fail","effectiveMode":"assisted","nativeOrder":["104.16.1.1"],"authorityActionId":"104.16.1.2"}
JSON
printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"}]' >"$TMP/native.json"
printf '%s\n' '{"reward":0.8}' >"$TMP/actual.json"
printf '%s\n' '[{"ip":"104.16.1.2"}]' >"$TMP/selected.json"
cfip_probe_one() { return 1; }
cfip_rill_holdout "$TMP/decision.json" "$TMP/native.json" "$TMP/actual.json" "$CFIP_TARGET_DOMAINS" 1 "$TMP/holdout.json"
test "$(jq -r '.performed' "$TMP/holdout.json")" = false
test "$(jq -r '.reason' "$TMP/holdout.json")" = probe_unavailable
test "$(jq -r '.feedbackEligible' "$TMP/holdout.json")" = false
test "$(jq -c . "$TMP/selected.json")" = '[{"ip":"104.16.1.2"}]'
echo 'Holdout failure is best-effort and non-blocking for the production run'
