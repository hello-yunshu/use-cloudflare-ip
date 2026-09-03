#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Eq 'evidenceAggregate' "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
grep -Eq 'confidenceLevel|confidenceReasons|nativeRillTop1Agreement|rillTop3Overlap' "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
grep -Eq 'currentContextFingerprint|contextChangedAt|holdoutFailures|comparableDecisions' "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
echo 'Intelligence status and diagnostics contract passed'
