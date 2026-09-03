#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_LOG_FILE="$TMP/log" CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json"
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
export CFIP_RILL_RUNTIME="$TMP/runtime" CFIP_RILL_DELAYED_FEEDBACK_SECONDS=60
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat >"$CFIP_RILL_RUNTIME" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
request="$(cat)"
jq -cn --arg id "$(jq -r .requestId <<<"$request")" '{requestId:$id,apiVersion:3,response:{kind:"result",output:{accepted:true}}}'
SH
chmod +x "$CFIP_RILL_RUNTIME"
cat >"$TMP/decision.json" <<'JSON'
{"decisionId":"lineage-decision","selectedActionId":"104.16.1.1","generation":1}
JSON
cat >"$TMP/outcome.json" <<'JSON'
{"candidateOutcome":"success","hostOutcome":"success","censored":false,"observedIp":"104.16.1.1","decisionActionId":"104.16.1.1","reward":0.8}
JSON
cfip_rill_queue_feedback "$TMP/decision.json" "$TMP/outcome.json"
old_lineage="$(jq -r '.[0].stateLineage' "$CFIP_RILL_PENDING_FILE")"
cfip_rill_rotate_lineage reset
test "$(jq -r '.lineageId' "$CFIP_RILL_STATE_META_FILE")" != "$old_lineage"
jq '.[].dueAt=0' "$CFIP_RILL_PENDING_FILE" | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"
cfip_rill_process_pending_feedback
test "$(jq -r 'length' "$CFIP_RILL_PENDING_FILE")" = 0
test "$(jq -r '.delayedRejected' "$CFIP_RILL_QUALIFICATION_FILE")" = 1
test ! -e "$CFIP_RILL_STATE"
echo 'Delayed feedback reset lineage rejection passed'
