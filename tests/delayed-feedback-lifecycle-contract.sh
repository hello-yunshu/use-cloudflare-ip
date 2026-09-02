#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_LOG_FILE="$TMP/log" CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_RILL_RUNTIME="$TMP/fake-runtime" CFIP_RILL_DELAYED_FEEDBACK_SECONDS=60 CFIP_RILL_DELAYED_FEEDBACK_EXPIRY_SECONDS=3600
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat > "$CFIP_RILL_RUNTIME" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
request="$(cat)"; id="$(jq -r '.requestId' <<<"$request")"
jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"result",output:{accepted:true}}}'
SH
chmod +x "$CFIP_RILL_RUNTIME"
cat > "$TMP/decision.json" <<'JSON'
{"decisionId":"restart-decision","selectedActionId":"104.16.1.1","generation":2}
JSON
cat > "$TMP/outcome.json" <<'JSON'
{"candidateOutcome":"success","hostOutcome":"success","censored":false,"observedIp":"104.16.1.1","decisionActionId":"104.16.1.1","reward":0.8}
JSON
cfip_rill_queue_feedback "$TMP/decision.json" "$TMP/outcome.json"
jq '.[].dueAt=0' "$CFIP_RILL_PENDING_FILE" | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"
CFIP_RUN_ID=restart-child bash -c '
  set -euo pipefail
  source "$1/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
  source "$1/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
  cfip_rill_process_pending_feedback
  test "$(cfip_rill_pending_count)" = 0
  test "$(jq -r .delayedCompleted "$CFIP_RILL_QUALIFICATION_FILE")" = 1
' _ "$ROOT"
CFIP_RUN_ID=expiry-child bash -c '
  set -euo pipefail
  source "$1/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
  source "$1/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
  schema="$(cfip_rill_schema_hash)"
  jq -cn --arg schema "$schema" --argjson decision "$(cat "$CFIP_STATUS_DIR/decision.json")" --argjson outcome "$(cat "$CFIP_STATUS_DIR/outcome.json")" \
    "[{dueAt:0,expiresAt:1,modelGeneration:2,featureSchemaHash:\$schema,decision:\$decision,outcome:\$outcome}]" | cfip_atomic_write "$CFIP_RILL_PENDING_FILE"
  cfip_rill_process_pending_feedback
  test "$(jq -r .delayedExpired "$CFIP_RILL_QUALIFICATION_FILE")" = 1
' _ "$ROOT"
echo 'Delayed feedback restart and expiry contract passed'
