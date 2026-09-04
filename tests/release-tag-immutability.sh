#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$ROOT/.github/workflows/release.yml"
grep -Eq 'Guard immutable release tag before asset upload' "$workflow"
grep -Eq 'git show-ref --verify' "$workflow"
grep -Eq 'immutable tag collision' "$workflow"
grep -Eq 'Verify published tag identity' "$workflow"
echo 'Release workflow contains pre-upload immutable tag guard and post-publish identity check'
