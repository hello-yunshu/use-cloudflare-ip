#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$ROOT/.github/workflows/release.yml"
grep -Fq 'git show-ref --verify' "$workflow"
grep -Fq 'immutable tag collision' "$workflow"
grep -Fq 'Verify published tag identity' "$workflow"
test "$(git -C "$ROOT" tag -l 'v2.*' | wc -l | tr -d ' ')" -gt 0
while IFS= read -r tag; do
    test -n "$(git -C "$ROOT" rev-parse "$tag^{commit}")"
done < <(git -C "$ROOT" tag -l 'v2.*')
echo 'Immutable tag contract passed'
