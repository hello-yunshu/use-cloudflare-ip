#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/status" "$TMP/runtime" "$TMP/run"
cat >"$TMP/run/input.json" <<'JSON'
[{"ip":"104.16.1.1","family":"ipv4","origin":"community","sources":["fixture"],"sourceCount":1,"stale":false}]
JSON
printf '[{"ip":"104.16.1.1"}]\n' >"$TMP/run/candidates.json"
printf '[{"ip":"104.16.1.1"}]\n' >"$TMP/run/native.json"
printf '[{"ip":"104.16.1.1"}]\n' >"$TMP/run/selected.json"
printf '[{"id":"fixture","stale":false,"parsedCount":1}]\n' >"$TMP/runtime/source-status.json"
printf '{"success":true}\n' >"$TMP/run/transaction.json"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/runtime/log" CFIP_LEGACY_BIN=/bin/false
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
CFIP_RUN_ID=status-fixture; CFIP_ENABLED=true; CFIP_MODE=passwall; CFIP_IP_COUNT=1; CFIP_IP_TYPE=ipv4; CFIP_SPEEDTEST_PROTOCOL=tcp; CFIP_CANDIDATE_BUDGET=128
CFIP_CANDIDATES_FILE="$TMP/run/candidates.json"; CFIP_INPUT_POOL_FILE="$TMP/run/input.json"; CFIP_NATIVE_FILE="$TMP/run/native.json"; CFIP_SELECTED_FILE="$TMP/run/selected.json"; CFIP_SOURCE_STATUS_FILE="$TMP/runtime/source-status.json"; CFIP_TXN_RESULT_FILE="$TMP/run/transaction.json"
cfip_rill_status_json(){ printf '%s\n' '{"available":false,"state":"disabled"}'; }
cfip_publisher_status_json(){ printf '%s\n' '{"success":true,"state":"disabled"}'; }
write_status false done success ""
jq -e '(.schemaVersion==2) and (.enabled==true) and (.running==true) and (.active_run==false) and (.candidate_budget==128) and (.measurement_input_count==1) and (.candidate_count==1) and (.eligible_count==1) and (.sources[0].id=="fixture") and (.publisher.state=="disabled")' "$CFIP_STATUS_FILE" >/dev/null
write_status true measuring running ""
jq -e '(.enabled==true) and (.running==true) and (.active_run==true) and (.phase=="measuring")' "$CFIP_STATUS_FILE" >/dev/null
echo 'v2 status contract tests passed'
