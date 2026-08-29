#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
for expr in '*/5 * * * *' '0 */6 * * *' '0 3 * * 1' '15 4 1,15 * *' '1-10/2 * * * *'; do cfip_valid_cron "$expr"; done
for expr in '60 * * * *' '* 24 * * *' '* * 0 * *' '* * * 13 *' '* * * * 8' '99 99 99 99 99' '1-80 * * * *' '*/0 * * * *' '* * * * ?'; do
    if cfip_valid_cron "$expr"; then
        echo "invalid cron accepted: $expr" >&2
        exit 1
    fi
done
echo 'cron semantic validation contract passed'
