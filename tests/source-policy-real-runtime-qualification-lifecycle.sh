#!/usr/bin/env bash
set -euo pipefail

BIN="${1:?compiled rill-runtime binary required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
export CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_RILL_RUNTIME="$BIN" CFIP_RILL_STATE="$TMP/state.json"
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
export CFIP_RILL_TIMEOUT_S=5 CFIP_RILL_SOURCE_PARTITION_KEY=source-policy CFIP_RILL_CANDIDATE_PARTITION_KEY=candidate CFIP_RUN_ID=candidate-seed
export CFIP_SOURCE_POLICY=official-heavy CFIP_SOURCE_POLICY_EXPLORATION_ENABLED=true
export CFIP_SOURCE_POLICY_EXPLORATION_CAP=1 CFIP_SOURCE_POLICY_EXPLORATION_EVERY=1 CFIP_IP_COUNT=1
export CFIP_SOURCE_STATUS_FILE="$TMP/source-status.json" CFIP_INPUT_POOL_FILE="$TMP/input-pool.json"
export CFIP_SOURCE_POLICY_FILE="$TMP/source-policy.json" CFIP_SOURCE_POLICY_QUALIFICATION_FILE="$TMP/source-policy-qualification.json"
export CFIP_SOURCE_POLICY_DECISION_FILE="$TMP/source-policy-decision.json" CFIP_RUN_HISTORY="$TMP/run-history"
mkdir -p "$CFIP_STATUS_DIR" "$CFIP_RUNTIME_DIR"
printf '%s\n' '[{"success":true,"stale":false}]' >"$CFIP_SOURCE_STATUS_FILE"
printf '%s\n' '[{"ip":"104.16.1.1"}]' >"$CFIP_INPUT_POOL_FILE"
printf '%s\n' '{"schemaVersion":2,"policies":{"official-heavy":{"ewmaReward":0.5,"samples":1}}}' >"$CFIP_SOURCE_POLICY_FILE"
printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4","avgLatencyMs":10,"downloadMBps":20,"lossRate":0,"cfstRank":1,"sourceCount":1,"sources":["official"],"probeSummary":{"connectMs":10,"tlsMs":10,"ttfbMs":20,"totalMs":40},"eligible":true}]' >"$TMP/candidate.json"
jq -cn '{candidateOutcome:"success"}' >"$TMP/source-outcome.json"

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"

# Seed a separate Candidate partition through the production ranking path so
# the later Source reset can prove it does not clear another learner.
cfip_rill_rank_shadow "$TMP/candidate.json" "$TMP/candidate-decision.json"

for i in $(seq 1 30); do
    attempt=0
    # Keep Native and the actual Runtime recommendation in disagreement so
    # every recorded sample has real bounded-exploration attribution. If the
    # learner selects the configured Native policy, complete that decision and
    # retry with the other stable Native policy before recording evidence.
    while :; do
        attempt=$((attempt + 1))
        export CFIP_RUN_ID="source-qualification-$i-$attempt"
        cfip_source_policy_decide
        test "$(jq -r '.partitionKey' "$CFIP_SOURCE_POLICY_DECISION_FILE")" = source-policy
        test "$(jq -r '.actions[0].features|length' "$CFIP_SOURCE_POLICY_DECISION_FILE")" = 6
        recommended="$(jq -r '.recommendedAction' "$CFIP_SOURCE_POLICY_DECISION_FILE")"
        if [[ "$recommended" != "$CFIP_SOURCE_POLICY" ]]; then
            break
        fi
        cfip_rill_policy_feedback "$CFIP_SOURCE_POLICY_DECISION_FILE" 0
        if [[ "$CFIP_SOURCE_POLICY" == balanced ]]; then
            CFIP_SOURCE_POLICY=official-heavy
        else
            CFIP_SOURCE_POLICY=balanced
        fi
    done
    cfip_source_policy_record "$TMP/source-outcome.json"
done

# The feedback calls above are real Runtime calls. Normal decide/feedback
# generation advances must not erase the rolling qualification window.
jq -e '.state == "shadow-qualified" and .windowSamples == 30 and .evaluatedDisagreements == 30 and .attributionCoverage == 1 and .recentErrors == 0 and .partitionKey == "source-policy" and .stateGeneration > 0' "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE" >/dev/null

source_generation="$(CFIP_RILL_PARTITION_KEY=source-policy cfip_rill_state_generation)"
schema="$(cfip_rill_schema_hash)"
reset_request="$(jq -cn --arg id source-explicit-reset --arg schema "$schema" --argjson generation "$source_generation" \
  '{requestId:$id,apiVersion:3,clientIdentity:{name:"cloudflare-ip",version:"2.0.0"},partitionKey:"source-policy",capability:"org.rill.preview.reset",featureSchemaHash:$schema,modelGeneration:2,stateGeneration:$generation,payloadLimit:1048576,request:{method:"reset",expectedStateGeneration:$generation}}')"
CFIP_RILL_PARTITION_KEY=source-policy cfip_rill_runtime_call "$reset_request" | jq -e '.response.kind == "reset" and .response.reset == true' >/dev/null
cfip_rill_rotate_lineage source_runtime_reset
test ! -e "$CFIP_SOURCE_POLICY_QUALIFICATION_FILE"

# Candidate state survives a Source-only Runtime reset.
jq -e 'any(.partitions[]; .clientIdentityName=="cloudflare-ip" and .partitionKey=="candidate")' "$CFIP_RILL_STATE" >/dev/null
echo 'Real Runtime source policy qualification, generation advance, and explicit reset lifecycle passed'
