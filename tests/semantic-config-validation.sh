#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"

CFIP_MODE=passwall
CFIP_PASSWALL_TARGET_DOMAIN=example.com
CFIP_CRON_INTERVAL=custom
uci_get() {
    if [[ "$1" == cf_ip.main.cron_custom ]]; then
        printf '%s' '*/15 * * * *'
    else
        printf '%s' "${2:-}"
    fi
}
validate_config

uci_get() {
    if [[ "$1" == cf_ip.main.cron_custom ]]; then
        printf '%s' '61m'
    else
        printf '%s' "${2:-}"
    fi
}
if validate_config; then
    echo 'invalid custom cron was accepted' >&2
    exit 1
fi

echo 'semantic configuration validation contract passed'
