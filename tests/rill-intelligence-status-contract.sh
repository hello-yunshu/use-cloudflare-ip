#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rg -q 'evidenceAggregate' "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
rg -q 'confidenceLevel|confidenceReasons|nativeRillTop1Agreement|rillTop3Overlap' "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
rg -q 'currentContextFingerprint|contextChangedAt|holdoutFailures|comparableDecisions' "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
echo 'Intelligence status and diagnostics contract passed'
