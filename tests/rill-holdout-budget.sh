#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_RILL_HOLDOUT_INTERVAL=5
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat >"$TMP/decision.json" <<'JSON'
{"effectiveMode":"assisted","nativeOrder":["104.16.1.1"],"authorityActionId":"104.16.1.2"}
JSON
jq -cn '[range(0;3)|{effectiveMode:"assisted",nativeTop1:"104.16.1.1",authorityActionId:"104.16.1.2",comparisonResult:"tie"}]' >"$CFIP_RILL_EVIDENCE_FILE"
set +e; cfip_rill_holdout_due "$TMP/decision.json"; rc=$?; set -e
test "$rc" = 1
jq -cn '[range(0;4)|{effectiveMode:"assisted",nativeTop1:"104.16.1.1",authorityActionId:"104.16.1.2",comparisonResult:"tie"}]' >"$CFIP_RILL_EVIDENCE_FILE"
set +e; cfip_rill_holdout_due "$TMP/decision.json"; rc=$?; set -e
test "$rc" = 0
echo 'Assisted holdout sampling is deterministic and bounded by the configured interval'
