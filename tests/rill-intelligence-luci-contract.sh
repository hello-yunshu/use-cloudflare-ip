#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; file="$ROOT/package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js"
node --check "$file"
rg -q 'Decision Evidence|Native Holdout|Decision Confidence|Learning Context|Unavailable / Native fallback' "$file"
rg -q 'native|Rill|wins|ties|losses|holdout|fallback' "$file"
echo 'Intelligence LuCI fail-safe evidence contract passed'
