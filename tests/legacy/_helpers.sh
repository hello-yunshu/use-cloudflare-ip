#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="$ROOT/package/luci-app-cloudflare-ip"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
