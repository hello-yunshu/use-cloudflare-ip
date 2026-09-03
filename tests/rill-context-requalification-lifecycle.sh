#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_RILL_MIN_FEEDBACK_SAMPLES=10 CFIP_RILL_MODE=assisted CFIP_RILL_ENABLED=true CFIP_TARGET_DOMAINS=one.example
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cfip_rill_context_guard; old_fp="$(cfip_rill_context_fingerprint)"; old_lineage="$(cfip_rill_lineage_id)"
cat >"$TMP/decision.json" <<'JSON'
{"decisionId":"lifecycle","effectiveMode":"assisted","nativeOrder":["1.1.1.1"],"authorityActionId":"2.2.2.2","confidenceLevel":"high","confidenceReasons":["qualification_valid"]}
JSON
printf '%s\n' '{"candidateOutcome":"success","reward":0.8}' >"$TMP/outcome.json"; printf '%s\n' '{"performed":true,"nativeHoldoutReward":0.7,"actualCandidateReward":0.8,"rewardDelta":0.1,"comparison":"win","failure":false}' >"$TMP/holdout.json"
for _ in $(seq 1 12); do cfip_rill_record_evaluation "$TMP/decision.json" "$TMP/outcome.json" "$TMP/holdout.json"; cfip_rill_record_qualification success true true false 0.8 "$TMP/outcome.json"; done
test "$(jq -r .state "$CFIP_RILL_QUALIFICATION_FILE")" = shadow-qualified
cfip_rill_status_json() { local q; q="$(jq -r '.state // "cold"' "$CFIP_RILL_QUALIFICATION_FILE" 2>/dev/null || printf cold)"; jq -cn --arg schema "$(sha256sum "$CFIP_RILL_SCHEMA_FILE" | awk '{print $1}')" --arg state "$q" '{available:true,state:"healthy",health:"healthy",healthHealthy:true,resourcePressure:false,featureSchemaVersion:2,featureSchemaHash:$schema,modelGeneration:2,qualificationState:$state,resetRequired:false}'; }
cfip_rill_assisted_ready
CFIP_TARGET_DOMAINS=two.example; cfip_rill_context_guard
new_fp="$(cfip_rill_context_fingerprint)"; new_lineage="$(cfip_rill_lineage_id)"
test "$old_fp" != "$new_fp"; test "$old_lineage" != "$new_lineage"; test -n "$(jq -r '.contextChangedAt // empty' "$CFIP_RILL_STATE_META_FILE")"; ! cfip_rill_assisted_ready
for _ in $(seq 1 12); do cfip_rill_record_evaluation "$TMP/decision.json" "$TMP/outcome.json" "$TMP/holdout.json"; cfip_rill_record_qualification success true true false 0.8 "$TMP/outcome.json"; done
test "$(jq -r .state "$CFIP_RILL_QUALIFICATION_FILE")" = shadow-qualified; cfip_rill_assisted_ready
echo 'Context change quarantines old learning and re-enters Assisted after fresh requalification'
