#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
makefile="$ROOT/package/luci-app-cloudflare-ip/Makefile"
test "$(sed -n 's/^PKG_VERSION:=//p' "$makefile" | head -n1)" = 2.6.0
test "$(sed -n 's/^PKG_RELEASE:=//p' "$makefile" | head -n1)" = 2
echo 'Package release bump contract passed for v2.6.0-2'
