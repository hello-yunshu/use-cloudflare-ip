#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log" CFIP_RUN_HISTORY="$TMP/history"
export CFIP_SOURCE_POLICY_FILE="$TMP/source-policy.json" CFIP_SOURCE_POLICY_DECISION_FILE="$TMP/decision.json"
export CFIP_SOURCE_STATUS_FILE="$TMP/source-status.json" CFIP_SOURCE_POLICY=balanced CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
cfip_rill_policy_decide() { jq -cn '{selectedActionId:"official-heavy",scores:[]}' >"$3"; }
printf '%s\n' '[]' >"$CFIP_SOURCE_STATUS_FILE"
CFIP_SOURCE_POLICY_EXPLORATION_ENABLED=false CFIP_SOURCE_POLICY_EXPLORATION_CAP=0 cfip_source_policy_decide
test "$CFIP_SOURCE_POLICY_EXECUTED" = balanced
test "$CFIP_SOURCE_POLICY_EXPLORATION" = false
CFIP_SOURCE_POLICY_EXPLORATION_ENABLED=true CFIP_SOURCE_POLICY_EXPLORATION_CAP=1 cfip_source_policy_decide
test "$CFIP_SOURCE_POLICY_RECOMMENDED" = official-heavy
test "$CFIP_SOURCE_POLICY_EXECUTED" = official-heavy
test "$CFIP_SOURCE_POLICY_EXPLORATION" = true
echo 'Source policy exploration cap authority contract passed'
