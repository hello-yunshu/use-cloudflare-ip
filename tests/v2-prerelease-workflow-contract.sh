#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$ROOT/.github/workflows/release.yml"
grep -Fq 'release-channel.json' "$workflow"
grep -Eq 'channel.*!=.*prerelease' "$workflow"
grep -Fq 'prerelease: true' "$workflow"
grep -Fq 'make_latest: false' "$workflow"
echo 'v2 prerelease workflow contract passed'
