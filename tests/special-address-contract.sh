#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
for ip in 104.16.1.1 2606:4700::1111; do cfip_is_public_candidate "$ip"; done
for ip in 0.1.2.3 10.0.0.1 100.64.0.1 127.0.0.1 169.254.1.1 172.16.0.1 192.0.0.1 192.0.2.1 192.31.196.1 192.52.193.1 192.88.99.1 192.168.1.1 192.175.48.1 198.18.0.1 198.51.100.1 203.0.113.1 224.0.0.1 240.0.0.1 255.255.255.255; do ! cfip_is_public_candidate "$ip"; done
for ip in 2001:0::1 2001:1::1 2001:2::1 2001:3::1 2001:4:112::1 2001:10::1 2001:1f::1 2001:20::1 2001:2f::1 2001:30::1 2001:3f::1 2001:db8::1 2002::1 3ffe::1 3fff::1 5f00::1 64:ff9b::1 64:ff9b:1::1 100::1 100:0:0:1::1 2620:4f:8000::1; do ! cfip_is_public_candidate "$ip"; done
echo 'special-purpose address contract passed'
