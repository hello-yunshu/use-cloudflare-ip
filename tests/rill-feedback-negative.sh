#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CFIP_LOG_FILE="$TMP/log"
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_RILL_STATE="$TMP/state.json"
export CFIP_RILL_TIMEOUT_S=2
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v1.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

cat >"$TMP/decision.json" <<'JSON'
{"decisionId":"decision-negative","selectedActionId":"104.16.1.1","generation":1}
JSON
cat >"$TMP/outcome.json" <<'JSON'
{"validated":true,"reward":0.5}
JSON
cat >"$TMP/fake-runtime" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
request="$(cat)"
request_id="$(jq -r '.requestId' <<<"$request")"
case "${CFIP_NEGATIVE_CASE:?}" in
  malformed) printf '%s\n' 'not-json' ;;
  rejected-result) jq -cn --arg id "$request_id" '{requestId:$id,apiVersion:3,response:{kind:"result",output:{accepted:false}}}' ;;
  duplicate) jq -cn --arg id "$request_id" '{requestId:$id,apiVersion:3,response:{kind:"error",error:{code:"duplicateFeedback",retryable:false,message:"feedback was already applied"}}}' ;;
  unknown) jq -cn --arg id "$request_id" '{requestId:$id,apiVersion:3,response:{kind:"error",error:{code:"internal",retryable:false,message:"decision id is not pending"}}}' ;;
  stale) jq -cn --arg id "$request_id" '{requestId:$id,apiVersion:3,response:{kind:"error",error:{code:"incompatibleGeneration",retryable:false,message:"feedback generation is stale"}}}' ;;
  schema) jq -cn --arg id "$request_id" '{requestId:$id,apiVersion:3,response:{kind:"error",error:{code:"stateMismatch",retryable:false,message:"feature schema hash does not match"}}}' ;;
  mismatched-request) jq -cn '{requestId:"wrong-request",apiVersion:3,response:{kind:"result",output:{accepted:true}}}' ;;
  *) exit 2 ;;
esac
SH
chmod +x "$TMP/fake-runtime"
export CFIP_RILL_RUNTIME="$TMP/fake-runtime"

for test_case in duplicate unknown stale schema malformed rejected-result mismatched-request; do
  : >"$CFIP_LOG_FILE"
  export CFIP_NEGATIVE_CASE="$test_case" CFIP_RUN_ID="negative-$test_case"
  if cfip_rill_feedback "$TMP/decision.json" "$TMP/outcome.json"; then
    echo "feedback negative case unexpectedly succeeded: $test_case" >&2
    exit 1
  fi
  cat "$CFIP_LOG_FILE" >>"$TMP/all-log"
done

grep -Fq 'code=duplicateFeedback' "$TMP/all-log" || {
  echo 'duplicate feedback diagnostic was not recorded' >&2
  exit 1
}
echo 'Rill feedback negative acknowledgement tests passed'
