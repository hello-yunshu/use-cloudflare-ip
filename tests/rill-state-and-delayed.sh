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

echo 'Rill state migration and delayed feedback tests passed'
