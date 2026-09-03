#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" CFIP_RILL_PENDING_FILE="$TMP/pending.json" CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json" CFIP_TARGET_DOMAINS=one.example CFIP_RILL_DELAYED_FEEDBACK_SECONDS=600
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
cfip_rill_context_guard; old_lineage="$(cfip_rill_lineage_id)"; printf '%s\n' '{"decisionId":"old","selectedActionId":"1.1.1.1","generation":1}' >"$TMP/decision.json"; printf '%s\n' '{"candidateOutcome":"success","observedIp":"1.1.1.1","decisionActionId":"1.1.1.1"}' >"$TMP/outcome.json"
cfip_rill_queue_feedback "$TMP/decision.json" "$TMP/outcome.json" one.example; CFIP_TARGET_DOMAINS=two.example; cfip_rill_context_guard; new_lineage="$(cfip_rill_lineage_id)"
test "$old_lineage" != "$new_lineage"; test "$(jq -r '.lineageId' "$CFIP_RILL_STATE_META_FILE")" = "$new_lineage"; test "$(jq -r '.[0].stateLineage' "$CFIP_RILL_PENDING_FILE")" = "$old_lineage"; test "$(jq -r '.[0].rejectedReason' "$CFIP_RILL_PENDING_FILE")" = context_changed
sed 's/"old"/"new"/' "$TMP/decision.json" >"$TMP/new-decision.json"; cfip_rill_queue_feedback "$TMP/new-decision.json" "$TMP/outcome.json" two.example; test "$(jq -r '.[1].stateLineage' "$CFIP_RILL_PENDING_FILE")" = "$new_lineage"
echo 'Context transition rotates Candidate lineage and isolates delayed feedback'
