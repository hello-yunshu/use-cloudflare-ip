#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
sleep() { echo 'sleep unexpectedly called' >&2; return 99; }
CFIP_STARTUP_DELAY=random CFIP_SKIP_STARTUP_DELAY=true; apply_startup_delay
echo 'no-delay override contract passed'
