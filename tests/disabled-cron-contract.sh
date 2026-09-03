#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip"
awk '/if \[ "\$enabled" -eq 0 \]; then/{seen=1} seen && /cf_ip_cron_remove/{found=1} seen && /return 0/{exit(found ? 0 : 1)} END{if (!seen) exit 1}' "$INIT"
echo 'Disabled configuration removes stale cron entries contract passed'
