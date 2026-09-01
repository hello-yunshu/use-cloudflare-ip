#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CFIP_LOG_FILE="$TMP/log" CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
export CFIP_RILL_STATE="$TMP/state.json" CFIP_STATUS_DIR="$TMP"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

old_state="$(jq -cn --arg s '{"handlerStateVersion":2,"featureCount":8,"weights":[],"actions":{}}' \
  '{formatVersion:1,partitions:[{clientIdentityName:"cloudflare-ip",partitionKey:"default",handlerSnapshot:{state:($s|explode),stateGeneration:4}}]}')"
printf '%s\n' "$old_state" > "$CFIP_RILL_STATE"
cfip_rill_prepare_state
quarantine="$(find "$TMP" -maxdepth 1 -name 'state.json.quarantine.*' -type f -print -quit)"
test -n "$quarantine"
test "$(jq -r .resetRequired "$CFIP_RILL_STATE_META_FILE")" = true
test "$(jq -r .resetReason "$CFIP_RILL_STATE_META_FILE")" = feature_schema_v2_required

printf '%s\n' '{not-json' > "$CFIP_RILL_STATE"
cfip_rill_prepare_state
test "$(find "$TMP" -maxdepth 1 -name 'state.json.quarantine.*' -type f | wc -l | tr -d ' ')" -ge 2
test "$(jq -r .resetReason "$CFIP_RILL_STATE_META_FILE")" = invalid_or_legacy_snapshot

cat > "$TMP/decision.json" <<'JSON'
{"decisionId":"delayed-decision","selectedActionId":"104.16.1.1"}
JSON
cat > "$TMP/outcome.json" <<'JSON'
{"candidateOutcome":"success","hostOutcome":"success","censored":false,"observedIp":"104.16.1.1","decisionActionId":"104.16.1.1","reward":0.75}
JSON
cat > "$TMP/fake-runtime" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
id="$(jq -r .requestId)"
jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"result",output:{accepted:true}}}'
SH
chmod +x "$TMP/fake-runtime"
export CFIP_RILL_RUNTIME="$TMP/fake-runtime" CFIP_RUN_ID=delayed-run CFIP_RILL_DELAYED_FEEDBACK_SECONDS=600
cfip_rill_queue_feedback "$TMP/decision.json" "$TMP/outcome.json"
jq '.[].dueAt=0' "$CFIP_RILL_PENDING_FILE" | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"
cfip_rill_process_pending_feedback
test "$(cfip_rill_pending_count)" = 0
test "$(jq -r .delayedCompleted "$CFIP_RILL_QUALIFICATION_FILE")" = 1
test "$(jq -r .lastReward "$CFIP_RILL_QUALIFICATION_FILE")" = 0.75

# Delayed feedback must re-observe the selected candidate against the original
# domain set, rather than replaying the first observation forever.
printf '%s\n' '{"state":"cold","validFeedback":0,"attributedFeedback":0,"delayedCompleted":0,"errors":0,"candidateFailures":0,"window":[],"recentRewards":[]}' \
  | jq -c . | cfip_atomic_write "$CFIP_RILL_QUALIFICATION_FILE"
export CFIP_RILL_DELAYED_PROBE_TIMEOUT=1
cat > "$TMP/fresh-decision.json" <<'JSON'
{"decisionId":"fresh-delayed-decision","selectedActionId":"104.16.1.1","generation":7,"candidates":[{"ip":"104.16.1.1","family":"ipv4","lossRate":0.02,"downloadMBps":80}]}
JSON
cat > "$TMP/fresh-outcome.json" <<'JSON'
{"candidateOutcome":"success","hostOutcome":"success","censored":false,"observedIp":"104.16.1.1","decisionActionId":"104.16.1.1","probes":[{"family":"ipv4","domain":"old.example","success":true,"totalMs":900,"ttfbMs":400}]}
JSON
cfip_probe_one() {
  printf '%s\n' "$2" >> "$TMP/delayed-probes.log"
  jq -cn --arg domain "$2" '{success:true,family:"ipv4",domain:$domain,connectMs:10,tlsMs:10,ttfbMs:30,totalMs:60}'
}
cfip_rill_queue_feedback "$TMP/fresh-decision.json" "$TMP/fresh-outcome.json" 'fresh.example,second.example'
jq '.[].dueAt=0' "$CFIP_RILL_PENDING_FILE" | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"
cfip_rill_process_pending_feedback
test "$(wc -l < "$TMP/delayed-probes.log" | tr -d ' ')" = 2
test "$(sed -n '1p' "$TMP/delayed-probes.log")" = fresh.example
test "$(sed -n '2p' "$TMP/delayed-probes.log")" = second.example
test "$(jq -r '.window[-1].delayed' "$CFIP_RILL_QUALIFICATION_FILE")" = true
test "$(jq -r '.window[-1].rewardVersion // 2' "$CFIP_RILL_QUALIFICATION_FILE")" = 2

printf '%s\n' '{broken' > "$CFIP_RILL_PENDING_FILE"
cfip_rill_process_pending_feedback
test "$(find "$TMP" -maxdepth 1 -name 'rill-pending-feedback.json.quarantine.*' -type f | wc -l | tr -d ' ')" -ge 1
test "$(cfip_rill_pending_count)" = 0
cfip_rill_queue_feedback "$TMP/fresh-decision.json" "$TMP/fresh-outcome.json" 'fresh.example'
cfip_rill_queue_feedback "$TMP/fresh-decision.json" "$TMP/fresh-outcome.json" 'fresh.example'
test "$(cfip_rill_pending_count)" = 1

echo 'Rill state migration and delayed feedback tests passed'
