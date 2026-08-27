#!/usr/bin/env bash
set -euo pipefail
OUTPUT="${1:?manifest output path required}"
RESULTS="${RESULTS:?qualification job results JSON required}"
ARTIFACTS="${ARTIFACTS:-[]}"
ASSET_FILES="${ASSET_FILES:-[]}"
commit="${GITHUB_SHA:?GITHUB_SHA required}"; run_id="${GITHUB_RUN_ID:?GITHUB_RUN_ID required}"
release_eligible=false
if jq -e 'to_entries|all(.value.result=="success")' <<<"$RESULTS" >/dev/null; then release_eligible=true; fi
jq -n --arg commit "$commit" --arg runId "$run_id" --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson jobs "$RESULTS" --argjson artifacts "$ARTIFACTS" --argjson assetFiles "$ASSET_FILES" --argjson releaseEligible "$release_eligible" \
  '{schemaVersion:1,commit:$commit,runId:$runId,generatedAt:$generatedAt,jobs:$jobs,artifacts:$artifacts,assetFiles:$assetFiles,qualificationState:(if $releaseEligible then "automated-qualification" else "incomplete" end),releaseEligible:$releaseEligible}' >"$OUTPUT"
jq -e --arg commit "$commit" '.schemaVersion==1 and .commit==$commit and (.runId|length)>0 and (.jobs|type)=="object" and (.artifacts|type)=="array" and (.assetFiles|type)=="array" and (.releaseEligible|type)=="boolean"' "$OUTPUT" >/dev/null
echo "evidence manifest written: $OUTPUT"
