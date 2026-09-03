#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_LOG_FILE="$TMP/log" CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_RILL_STATE="$TMP/state.json"
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cat > "$TMP/decision.json" <<'JSON'
{"decisionId":"outcome-test","selectedActionId":"104.16.1.2"}
JSON
cat > "$TMP/fake-runtime" <<'SH'
#!/usr/bin/env bash
touch "${RILL_MARKER:?}"
id="$(jq -r .requestId)"
jq -cn --arg id "$id" '{requestId:$id,apiVersion:3,response:{kind:"result",output:{accepted:true}}}'
SH
chmod +x "$TMP/fake-runtime"
export CFIP_RILL_RUNTIME="$TMP/fake-runtime" RILL_MARKER="$TMP/called"

cat > "$TMP/host-failure.json" <<'JSON'
{"candidateOutcome":"unknown","hostOutcome":"failure","censored":true,"observedIp":"104.16.1.1","decisionActionId":"104.16.1.1","reward":-1}
JSON
cfip_rill_feedback "$TMP/decision.json" "$TMP/host-failure.json"
test ! -e "$RILL_MARKER"

cat > "$TMP/wrong-candidate.json" <<'JSON'
{"candidateOutcome":"failure","hostOutcome":"success","censored":false,"observedIp":"104.16.1.1","decisionActionId":"104.16.1.1","reward":-1}
JSON
if cfip_rill_feedback "$TMP/decision.json" "$TMP/wrong-candidate.json"; then
    echo 'mismatched candidate outcome unexpectedly accepted' >&2
    exit 1
fi
test ! -e "$RILL_MARKER"
echo 'Rill candidate/host outcome attribution tests passed'
