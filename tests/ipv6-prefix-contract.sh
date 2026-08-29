#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"

assert_in_prefix() {
    cfip_ipv6_in_prefix "$1" "$2" || { echo "expected prefix match: $1 in $2" >&2; exit 1; }
}

assert_not_in_prefix() {
    if cfip_ipv6_in_prefix "$1" "$2"; then
        echo "unexpected prefix match: $1 in $2" >&2
        exit 1
    fi
}

assert_in_prefix 64:FF9B::1 64:ff9b::/96
assert_in_prefix 0064:ff9b:0000:0000:0000:0000:0000:0001 64:ff9b::/96
assert_in_prefix 2001:db8:ffff::1 2001:DB8::/32
assert_in_prefix 2001:0:8000::1 2001::/23
assert_in_prefix 2001:01ff:ffff::1 2001::/23
assert_not_in_prefix 2001:0200::1 2001::/23
assert_in_prefix 2001:2:1::1 2001:2::/47
assert_not_in_prefix 2001:2:2::1 2001:2::/47
assert_in_prefix 2001:4860:4860::8888 0::/0
assert_in_prefix 2001:4860:4860:: 2001:4860:4860::/128
assert_not_in_prefix 2001:4860:4860::8844 2001:4860:4860::/128
assert_in_prefix ::1 ::1/128

for ip in 64:ff9b::1 64:ff9b:1::1 100::1 100:0:0:1::1 2001:db8::1 fc00::1 fe80::1 ff00::1 3ffe::1 3fff::1 5f00::1 2620:4f:8000::1; do
    if cfip_is_public_candidate "$ip"; then
        echo "reserved IPv6 accepted: $ip" >&2
        exit 1
    fi
done

for ip in 2606:4700::1111 2606:4700:4700::1111 2606:4700:100::1 2001:4860:4860::8888; do
    cfip_is_public_candidate "$ip" || { echo "public IPv6 rejected: $ip" >&2; exit 1; }
done

echo 'IPv6 prefix contract passed'
