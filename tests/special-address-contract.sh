#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
for ip in 104.16.1.1 2606:4700::1111; do cfip_is_public_candidate "$ip"; done
for ip in 192.88.99.1 192.31.196.1 192.52.193.1 192.175.48.1 2001:1::1 2001:2::1 2001:10::1 2002::1 3fff::1 5f00::1; do ! cfip_is_public_candidate "$ip"; done
echo 'special-purpose address contract passed'
