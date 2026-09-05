#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="${1:-$ROOT/docker/2.3/results/replay-evidence.json}"
SUMMARY="${2:-${OUTPUT%.json}-summary.json}"
bash "$ROOT/docker/2.3/replay-scenarios.sh" "$ROOT/docker/2.3/fixtures/scenarios.json" "$OUTPUT"
bash "$ROOT/docker/2.3/summarize-evidence.sh" "$OUTPUT" "$SUMMARY"
printf 'Docker replay complete: %s\n' "$OUTPUT"
