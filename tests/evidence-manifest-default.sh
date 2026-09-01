#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
RESULTS='{"host-contract":{"result":"failure"}}' \
  GITHUB_SHA=0123456789012345678901234567890123456789 GITHUB_RUN_ID=123 \
  bash "$ROOT/tests/evidence-manifest.sh" "$TMP/manifest.json"
jq -e '.releaseEligible==false and .rill=={} and .qualificationState=="incomplete"' "$TMP/manifest.json" >/dev/null
echo 'Evidence manifest default JSON contract passed'
