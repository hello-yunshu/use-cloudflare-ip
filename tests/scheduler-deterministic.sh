#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
a="$(cfip_sample_ipv4_cidr 104.16.0.0/13 seed-a)"; b="$(cfip_sample_ipv4_cidr 104.16.0.0/13 seed-a)"; c="$(cfip_sample_ipv4_cidr 104.16.0.0/13 seed-b)"
test "$a" = "$b"; test "$a" != "$c"; cfip_is_public_candidate "$a"
a="$(cfip_sample_ipv6_cidr 2606:4700::/32 seed-a)"; b="$(cfip_sample_ipv6_cidr 2606:4700::/32 seed-a)"; test "$a" = "$b"; [[ "$a" == 2606:4700:* ]]
echo 'deterministic scheduler sampling contract passed'
