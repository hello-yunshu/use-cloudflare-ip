#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INPUT="${1:-$ROOT/docker/2.3/results/replay-evidence.json}"
OUTPUT="${2:-$ROOT/docker/2.3/results/replay-summary.json}"
"$ROOT/docker/2.3/summarize-evidence.sh" "$INPUT" "$OUTPUT"
printf 'validated replay evidence: %s\n' "$INPUT"
