#!/usr/bin/env bash
set -euo pipefail

BIN="${1:?compiled rill-runtime binary required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_RILL_RUNTIME="$BIN" CFIP_RILL_STATE="$TMP/state.json"
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
export CFIP_RILL_TIMEOUT_S=5 CFIP_RUN_ID=multi-learner-1
export CFIP_SOURCE_STATUS_FILE="$TMP/source-status.json" CFIP_SOURCE_POLICY_FILE="$TMP/source-policy.json"
export CFIP_SOURCE_POLICY_QUALIFICATION_FILE="$TMP/source-policy-qualification.json"
mkdir -p "$CFIP_STATUS_DIR" "$CFIP_RUNTIME_DIR"
printf '%s\n' '[]' >"$CFIP_SOURCE_STATUS_FILE"

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

native="$TMP/native.json"
cat >"$native" <<'EOF_NATIVE'
[
  {"ip":"104.16.1.1","family":"ipv4","nativeRank":1,"avgLatencyMs":10,"downloadMBps":20,"lossRate":0,"cfstRank":1,"sourceCount":1,"sources":["official"],"probeSummary":{"connectMs":10,"tlsMs":10,"ttfbMs":20,"totalMs":40},"eligible":true},
  {"ip":"104.16.2.2","family":"ipv4","nativeRank":2,"avgLatencyMs":20,"downloadMBps":15,"lossRate":0,"cfstRank":2,"sourceCount":1,"sources":["community"],"probeSummary":{"connectMs":20,"tlsMs":20,"ttfbMs":30,"totalMs":60},"eligible":true}
]
EOF_NATIVE

source_round() {
    local suffix="$1" decision
    decision="$TMP/source-$suffix.json"
    export CFIP_RUN_ID="source-$suffix"
    CFIP_SOURCE_POLICY_DECISION_FILE="$decision" cfip_source_policy_decide
    test "$(jq -r '.partitionKey' "$decision")" = source-policy
    test "$(jq -r '.actions[0].features|length' "$decision")" = 6
    test "$(jq -r '[.actions[].features[5]]|unique|length' "$decision")" = 5
    cfip_rill_policy_feedback "$decision" 0.7
}

candidate_round() {
    local suffix="$1" decision outcome
    decision="$TMP/candidate-$suffix.json"
    outcome="$TMP/candidate-$suffix-outcome.json"
    export CFIP_RUN_ID="candidate-$suffix"
    cfip_rill_rank_shadow "$native" "$decision"
    test "$(jq -r '.partitionKey' "$decision")" = candidate
    test "$(jq -r '.candidates[0].ip' "$decision")" = 104.16.1.1
    jq -cn --arg ip "$(jq -r '.selectedActionId' "$decision")" '{candidateOutcome:"success",hostOutcome:"success",censored:false,observedIp:$ip,decisionActionId:$ip,reward:0.6}' >"$outcome"
    cfip_rill_feedback "$decision" "$outcome"
}

source_round 1
candidate_round 1
source_round 2
candidate_round 2

# Every wrapper call above starts a fresh Runtime process. Repeat both learners
# after the state file has already been populated to prove restart persistence.
source_round 3
candidate_round 3

jq -e '
  ([.partitions[] | select(.clientIdentityName=="cloudflare-ip" and .partitionKey=="source-policy")][0]) as $source |
  ([.partitions[] | select(.clientIdentityName=="cloudflare-ip" and .partitionKey=="candidate")][0]) as $candidate |
  ($source.handlerSnapshot.state|implode|fromjson) as $sourceState |
  ($candidate.handlerSnapshot.state|implode|fromjson) as $candidateState |
  ($source.handlerSnapshot.stateGeneration > 0 and $candidate.handlerSnapshot.stateGeneration > 0) and
  ($sourceState.featureCount == 6 and $candidateState.featureCount == 22) and
  ($sourceState.feedback >= 3 and $candidateState.feedback >= 3) and
  (($source.completedDecisions|length) >= 3 and ($candidate.completedDecisions|length) >= 3) and
  ($sourceState.featureCount != $candidateState.featureCount)
' "$CFIP_RILL_STATE" >/dev/null

echo 'Real Runtime multi-learner partition isolation and restart lifecycle passed'
