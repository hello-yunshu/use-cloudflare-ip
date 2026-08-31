#!/usr/bin/env bash
set -euo pipefail
OUTPUT="${1:?manifest output path required}"
RESULTS="${RESULTS:?qualification job results JSON required}"
ARTIFACTS="${ARTIFACTS:-[]}"
ASSET_FILES="${ASSET_FILES:-[]}"
RILL_EVIDENCE="${RILL_EVIDENCE:-}"
[[ -n "$RILL_EVIDENCE" ]] || RILL_EVIDENCE='{}'
commit="${GITHUB_SHA:?GITHUB_SHA required}"; run_id="${GITHUB_RUN_ID:?GITHUB_RUN_ID required}"
release_eligible=false
if jq -e 'to_entries|all(.value.result=="success")' <<<"$RESULTS" >/dev/null; then release_eligible=true; fi
jq -n --arg commit "$commit" --arg runId "$run_id" --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson jobs "$RESULTS" --argjson artifacts "$ARTIFACTS" --argjson assetFiles "$ASSET_FILES" --argjson rill "$RILL_EVIDENCE" --argjson releaseEligible "$release_eligible" \
  '{schemaVersion:1,commit:$commit,runId:$runId,generatedAt:$generatedAt,jobs:$jobs,artifacts:$artifacts,assetFiles:$assetFiles,rill:$rill,qualificationState:(if $releaseEligible then "automated-qualification" else "incomplete" end),releaseEligible:$releaseEligible}' >"$OUTPUT"
jq -e --arg commit "$commit" '.schemaVersion==1 and .commit==$commit and (.runId|length)>0 and (.jobs|type)=="object" and (.artifacts|type)=="array" and (.assetFiles|type)=="array" and (.rill|type)=="object" and (.releaseEligible|type)=="boolean" and ((.releaseEligible==false) or (.rill.schemaVersion==1 and .rill.package.repository=="hello-yunshu/rill-openwrt-packages" and (.rill.package.commit|test("^[0-9a-fA-F]{40}$")) and (.rill.package.qualificationRunId|type)=="number" and (.rill.package.qualificationManifestSha256|test("^[0-9a-fA-F]{64}$")) and .rill.stablePackageQualification=="PASS" and .rill.previewRuntimeIntegration=="PASS" and (.rill.stableCommit|test("^[0-9a-fA-F]{40}$")) and (.rill.previewCommit|test("^[0-9a-fA-F]{40}$")) and .rill.stableCommit != .rill.previewCommit and (.rill.runtime.version|type)=="string" and (.rill.runtime.tag|type)=="string" and (.rill.runtime.commit|test("^[0-9a-fA-F]{40}$")) and ((.rill.runtime.sourceArchiveSha256|test("^[0-9a-fA-F]{64}$")) or (.rill.runtime.tag=="preview-exact-commit" and .rill.runtime.sourceArchiveSha256=="not-applicable-preview")) and (.rill.runtime.binarySha256|test("^[0-9a-fA-F]{64}$")) and .rill.integration.status=="pass" and .rill.integration.sameRelease==false))' "$OUTPUT" >/dev/null
echo "evidence manifest written: $OUTPUT"
