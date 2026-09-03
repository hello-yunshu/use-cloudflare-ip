#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"
trap 'rc=$?; if ((rc != 0)); then cat "$TMP/log" 2>/dev/null || true; fi; rm -rf "$TMP"; exit "$rc"' EXIT
mkdir -p "$TMP/bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$TMP/bin/uci"; chmod +x "$TMP/bin/uci"; export PATH="$TMP/bin:$PATH"
cat >"$TMP/runtime" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
request="$(cat)"; method="$(jq -r '.request.method // empty' <<<"$request")"; id="$(jq -r '.requestId' <<<"$request")"; schema="$(jq -r '.featureSchemaHash' <<<"$request")"
case "$method" in
  handshake) jq -cn --arg id "$id" --arg schema "$schema" '{requestId:$id,apiVersion:3,modelGeneration:2,stateGeneration:0,response:{kind:"handshake",handlerApiVersion:2,capabilities:["org.rill.preview.decide","org.rill.preview.feedback"],featureSchemaHash:$schema,channel:"preview",runtimeIdentity:{version:"test"}}}' ;;
  health) jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"health",status:"healthy",healthy:true,reasonCodes:[]}}' ;;
  inspect) jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"inspection",summary:{resourceUtilization:{stateBytes:1,pendingDecisions:0,completedDecisions:1},resourceProfile:{maxModelStateBytes:1000,maxPendingDecisions:100,maxCompletedDecisions:100}}}}' ;;
  decide) jq -cn --arg id "$id" --arg selected "2.2.2.2" --argjson generation "$(jq '.stateGeneration + 1' <<<"$request")" '{requestId:$id,apiVersion:3,modelGeneration:2,stateGeneration:$generation,response:{kind:"result",output:{accepted:true,selectedActionId:$selected,scores:[{id:"2.2.2.2",score:0.9},{id:"1.1.1.1",score:0.1}]}}}' ;;
  feedback) jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"result",output:{accepted:true}}}' ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TMP/runtime"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_STATUS_DIR="$TMP/state" CFIP_RUNTIME_DIR="$TMP/runtime-dir" CFIP_LOG_FILE="$TMP/log" CFIP_RILL_STATE="$TMP/state/rill-state.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/state/qualification.json" CFIP_RILL_EVIDENCE_FILE="$TMP/state/evidence.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_RILL_RUNTIME="$TMP/runtime" CFIP_RILL_MIN_FEEDBACK_SAMPLES=10 CFIP_RILL_DELAYED_FEEDBACK_SECONDS=60 CFIP_SKIP_STARTUP_DELAY=true
export CFIP_VALIDATE_CANDIDATE_JSON='{"cf_ip.main.enabled":"1","cf_ip.main.mode":"passwall","cf_ip.main.ip_count":"1","cf_ip.main.ip_type":"ipv4","cf_ip.main.speedtest_protocol":"tcp","cf_ip.main.measurement_timeout":"20","cf_ip.main.candidate_budget":"100","cf_ip.main.probe_top_count":"2","cf_ip.main.max_probe_count":"2","cf_ip.main.probe_timeout":"1","cf_ip.main.probe_concurrency":"1","cf_ip.main.probe_batch_size":"1","cf_ip.main.source_policy":"balanced","cf_ip.main.reuse_enabled":"0","cf_ip.main.stop_service":"0","cf_ip.main.cron_interval":"1h","cf_ip.rill.enabled":"1","cf_ip.rill.mode":"assisted","cf_ip.rill.runtime":"'"$TMP/runtime"'","cf_ip.rill.state_file":"'"$TMP/state/rill-state.json"'","cf_ip.rill.min_feedback_samples":"10","cf_ip.rill.delayed_feedback_minutes":"1","cf_ip.passwall.target_domain":"one.example"}'
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
ensure_cfst() { :; }
cfip_prepare_candidate_pool() { printf '%s\n' '[{"ip":"1.1.1.1","family":"ipv4"},{"ip":"2.2.2.2","family":"ipv4"}]' >"$1"; printf '%s\n' '1.1.1.1' '2.2.2.2' >"$2"; printf '%s\n' '[]' >"$3"; }
run_cfst() { printf '%s\n' '[{"ip":"1.1.1.1","family":"ipv4","cfstRank":1},{"ip":"2.2.2.2","family":"ipv4","cfstRank":2}]' >"$CFIP_CANDIDATES_FILE"; }
cfip_rill_probe_priority() { cp "$1" "$2"; }; cfip_probe_candidates_batched() { jq 'map(. + {eligible:true,lossRate:0,downloadMBps:20,probeSummary:{totalMs:40,ttfbMs:20}})' "$1" >"$2"; }; cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:true,connectMs:10,tlsMs:10,ttfbMs:20,totalMs:40}'; }
cfip_rill_update_history() { :; }; cfip_reuse_try_current() { return 1; }; cfip_reuse_write_event() { :; }; cfip_publish_result() { :; }; write_status() { :; }; remember_history() { :; }
cfip_txn_prepare() { CFIP_TXN_DIR="$TMP/txn"; mkdir -p "$CFIP_TXN_DIR"; CFIP_TXN_MODE="$1"; CFIP_TXN_COMMITTED=false; }; cfip_txn_apply() { :; }; cfip_txn_commit() { CFIP_TXN_COMMITTED=true; CFIP_TXN_STATE=COMMITTED; CFIP_TXN_DIR=""; }; cfip_txn_rollback() { :; }
cfip_post_apply_probe() { local selected="$1" ip; ip="$(jq -r '.[0].ip' "$selected")"; jq -cn --arg ip "$ip" '{schemaVersion:2,validated:true,candidateOutcome:"success",hostOutcome:"success",censored:false,observedIp:$ip,decisionActionId:$ip,reward:0.8,probes:[{ip:$ip,success:true,totalMs:40,ttfbMs:20}]}' >"$4"; }
run_one() { run_v2 >/dev/null; ls -td "$CFIP_RUNTIME_DIR"/run-* | head -n1; }; due_all_pending() { [[ -s "$CFIP_RILL_PENDING_FILE" ]] || return 0; jq 'map(.dueAt=0)' "$CFIP_RILL_PENDING_FILE" | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"; }

first_run="$(run_one)"; decision="$first_run/decision.json"
test "$(jq -r '.requestedMode' "$decision")" = assisted; test "$(jq -r '.effectiveMode' "$decision")" = shadow; test "$(jq -r '.authorityActionId' "$decision")" = 1.1.1.1; test "$(jq -r '.selectedActionId' "$decision")" = 2.2.2.2
test "$(jq -r '.observedIp' "$first_run/shadow-outcome.json")" = 2.2.2.2; test "$(jq -r '.[0].outcome.observedIp' "$CFIP_RILL_PENDING_FILE")" = 2.2.2.2
old_fp="$(cfip_rill_context_fingerprint)"; old_lineage="$(cfip_rill_lineage_id)"
for _ in $(seq 2 12); do due_all_pending; run_one >/dev/null; done
if [[ "$(jq -r '.state' "$CFIP_RILL_QUALIFICATION_FILE")" != shadow-qualified ]]; then cat "$CFIP_RILL_QUALIFICATION_FILE" >&2; cat "$CFIP_RILL_PENDING_FILE" >&2; exit 1; fi
assisted_run="$(run_one)"; test "$(jq -r '.effectiveMode' "$assisted_run/decision.json")" = assisted
export CFIP_VALIDATE_CANDIDATE_JSON="${CFIP_VALIDATE_CANDIDATE_JSON/one.example/two.example}"
new_context="$(run_one)"; new_fp="$(cfip_rill_context_fingerprint)"; new_lineage="$(cfip_rill_lineage_id)"
test "$old_fp" != "$new_fp"; test "$old_lineage" != "$new_lineage"; test "$(jq -r '.requestedMode' "$new_context/decision.json")" = assisted; test "$(jq -r '.effectiveMode' "$new_context/decision.json")" = shadow; test "$(jq -r '.authorityActionId' "$new_context/decision.json")" = 1.1.1.1; test "$(jq -r '.observedIp' "$new_context/shadow-outcome.json")" = 2.2.2.2
for _ in $(seq 2 12); do due_all_pending; run_one >/dev/null; done
test "$(jq -r '.state' "$CFIP_RILL_QUALIFICATION_FILE")" = shadow-qualified
assisted_after_context="$(run_one)"; test "$(jq -r '.effectiveMode' "$assisted_after_context/decision.json")" = assisted
echo 'Production-equivalent run_v2 context requalification, fallback Shadow observation, delayed attribution, and Assisted recovery passed'
