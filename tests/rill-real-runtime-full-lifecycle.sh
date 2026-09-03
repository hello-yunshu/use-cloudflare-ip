#!/usr/bin/env bash
set -euo pipefail
BIN="${1:?actual packaged rill-runtime binary required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then cat "$TMP/log" 2>/dev/null || true; fi; rm -rf "$TMP"; exit "$rc"' EXIT
test -x "$BIN"
export CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log" CFIP_RUN_ID=full-lifecycle-1
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_RILL_RUNTIME="$BIN" CFIP_RILL_STATE="$TMP/rill-state.json" CFIP_RILL_TIMEOUT_S=5
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_TARGET_DOMAINS='one.example,ONE.example' CFIP_SPEEDTEST_PROTOCOL=tcp CFIP_IP_TYPE=ipv4
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
mkdir -p "$CFIP_RUNTIME_DIR"
cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:true,connectMs:10,tlsMs:10,ttfbMs:20,totalMs:40}'; }
cat > "$TMP/native.json" <<'JSON'
[{"ip":"104.16.1.1","family":"ipv4","nativeRank":1,"avgLatencyMs":10,"downloadMBps":20,"lossRate":0,"probeSummary":{"connectMs":10,"tlsMs":10,"ttfbMs":20,"totalMs":40},"eligible":true},
 {"ip":"104.16.1.2","family":"ipv4","nativeRank":2,"avgLatencyMs":12,"downloadMBps":18,"lossRate":0,"probeSummary":{"connectMs":10,"tlsMs":10,"ttfbMs":25,"totalMs":45},"eligible":true}]
JSON
cfip_rill_context_guard
cfip_rill_rank_shadow "$TMP/native.json" "$TMP/decision.json"
test "$(jq -r .generation "$TMP/decision.json")" = 1
inspect="$(cfip_rill_inspect_json)"; test "$(jq -r 'type=="object"' <<<"$inspect")" = true; generation_after_inspect="$(cfip_rill_state_generation)"; test "$generation_after_inspect" -gt 1
printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"}]' > "$TMP/selected.json"
cfip_post_apply_probe "$TMP/selected.json" one.example 1 "$TMP/outcome.json"
cfip_rill_feedback "$TMP/decision.json" "$TMP/outcome.json"
generation_after_feedback="$(cfip_rill_state_generation)"; test "$generation_after_feedback" -gt "$generation_after_inspect"
CFIP_RUN_ID=full-lifecycle-2 cfip_rill_rank_shadow "$TMP/native.json" "$TMP/decision-2.json"
test "$(jq -r .generation "$TMP/decision-2.json")" -gt "$generation_after_feedback"
CFIP_RILL_DELAYED_FEEDBACK_SECONDS=600 cfip_rill_queue_feedback "$TMP/decision-2.json" "$TMP/outcome.json" one.example
test "$(cfip_rill_pending_count)" = 1
CFIP_TARGET_DOMAINS='two.example'; cfip_rill_context_guard
test "$(jq -r '.[0].rejectedReason' "$CFIP_RILL_PENDING_FILE")" = context_changed
cfip_rill_process_pending_feedback
test "$(cfip_rill_pending_count)" = 0
test "$(jq -r '.delayedRejected' "$CFIP_RILL_QUALIFICATION_FILE")" = 1
CFIP_RUN_ID=full-lifecycle-3 cfip_rill_rank_shadow "$TMP/native.json" "$TMP/decision-new-context.json"
test "$(jq -r .generation "$TMP/decision-new-context.json")" = 1
test "$(jq -r .contextChanged "$CFIP_RILL_STATE_META_FILE")" = true
new_selected_ip="$(jq -r '.selectedActionId' "$TMP/decision-new-context.json")"
jq -cn --arg ip "$new_selected_ip" '[{ip:$ip,family:"ipv4"}]' > "$TMP/selected-new-context.json"
cfip_post_apply_probe "$TMP/selected-new-context.json" two.example 1 "$TMP/outcome-new-context.json"
cfip_rill_feedback "$TMP/decision-new-context.json" "$TMP/outcome-new-context.json"
test "$(jq -r '.generation' "$TMP/rill-state.json")" -gt 1
test "$(jq -r '.stateLineage' "$TMP/decision-new-context.json")" != "$(jq -r '.stateLineage' "$TMP/decision-2.json")"
echo 'Actual packaged Runtime full lifecycle, restart, inspect, delayed feedback, and context isolation passed'
