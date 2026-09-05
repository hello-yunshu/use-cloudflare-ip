#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
channel="$ROOT/release-channel.json"
workflow="$ROOT/.github/workflows/release.yml"
jq -e '(.schemaVersion == 1) and (.channel == "prerelease") and ((.reason|type) == "string") and ((.reason|length) > 0)' "$channel" >/dev/null
grep -Fq 'prerelease: true' "$workflow"
grep -Fq 'make_latest: false' "$workflow"
grep -Fq 'explicit Stable Gate' "$workflow"
echo 'Prerelease channel contract passed'
