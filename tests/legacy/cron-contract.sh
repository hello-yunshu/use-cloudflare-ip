#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
source "$PKG/root/usr/libexec/cf-ip/common.sh"
for cron in '*/15 0-6 * * 1-5' '0 0 1,15 * *'; do cfip_valid_cron "$cron"; done
for cron in '0 0 * * * extra' '0 0 * * *;id' $'0 0 * * *\n/etc/passwd'; do
  if cfip_valid_cron "$cron"; then
    echo "invalid cron accepted: $cron" >&2
    exit 1
  fi
done
echo 'legacy cron syntax contract passed'
