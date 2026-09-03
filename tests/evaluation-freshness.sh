#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVALUATION_MAX_AGE_SECONDS=100 CFIP_RILL_FAKE_NOW=1000
export CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

jq -cn '{state:"shadow-qualified",evaluationHealth:"healthy",evaluationFreshAt:800,evaluationWindow:[{comparisonResult:"win",rewardDelta:0.1,at:800}],trainingWindow:[],window:[]}' >"$CFIP_RILL_QUALIFICATION_FILE"
if cfip_rill_qualified; then
    echo 'stale evaluation remained qualified' >&2
    exit 1
fi
export CFIP_RILL_FAKE_NOW=850
cfip_rill_qualified
echo 'Evaluation freshness downgrades stale qualification and permits fresh recovery'
