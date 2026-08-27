#!/usr/bin/env bash
set -euo pipefail
BIN="${1:?adapter binary required}"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; STATE="$TMP/state.json"
run_adapter(){ if [ -n "${RUNNER:-}" ]; then $RUNNER "$BIN" "$@"; else "$BIN" "$@"; fi; }
cat >"$TMP/rank.json" <<'JSON'
{"schemaVersion":1,"runId":"decision-1","createdAt":2000000000,"candidates":[{"ip":"104.16.1.1","nativeRank":1,"avgLatencyMs":30,"downloadMBps":20,"lossRate":0,"probeSummary":{"connectMs":10,"tlsMs":20,"ttfbMs":30,"totalMs":40}},{"ip":"104.16.1.2","nativeRank":2,"avgLatencyMs":40,"downloadMBps":15,"lossRate":0.1,"probeSummary":{"connectMs":20,"tlsMs":30,"ttfbMs":50,"totalMs":70}}]}
JSON
run_adapter status --state "$STATE" | jq -e '.success==true and .rillVersion=="1.5.3" and .stateSchemaVersion==2' >/dev/null
run_adapter rank --state "$STATE" --input "$TMP/rank.json" >"$TMP/rank-out.json"
jq -e '.success==true and .generation==1 and (.candidates|length)==2 and (.decisionId|length)==32' "$TMP/rank-out.json" >/dev/null
cat >"$TMP/feedback.json" <<'JSON'
{"schemaVersion":1,"decision":{"runId":"decision-1","generation":1},"outcome":{"validated":true,"observedAt":2000000001,"ip":"104.16.1.1","reward":0.8}}
JSON
run_adapter feedback --state "$STATE" --input "$TMP/feedback.json" | jq -e '.success==true and .accepted==true and .generation==2' >/dev/null
if run_adapter feedback --state "$STATE" --input "$TMP/feedback.json" >/dev/null 2>&1; then echo 'duplicate feedback unexpectedly accepted' >&2; exit 1; fi
printf '{broken json\n' >"$STATE"; if run_adapter status --state "$STATE" | jq -e '.success==true' >/dev/null 2>&1; then echo 'corrupt state unexpectedly accepted' >&2; exit 1; fi
echo 'Rill adapter smoke passed'
