#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
. "$repo_dir/cf-openwrt-auto.sh"

restart_service() {
    :
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

OPENCLASH_CONFIG="$tmp_dir/clash-proxies.yaml"
OPENCLASH_NAME_SUFFIX=" [CF-{n}]"
OPENCLASH_TRANSPORT_FILTER=""
FAST_IPS=("104.16.1.1")
IP_COUNT=1

target_domains=()
for type in vless vmess trojan; do
    for network in ws xhttp grpc h2 http; do
        target_domains+=("${network}.${type}.uicbrmo.hey.run")
    done
done
OPENCLASH_TARGET_DOMAIN="$(IFS=,; printf '%s' "${target_domains[*]}")"

{
    printf 'proxies:\n'
    for type in vless vmess trojan; do
        for network in ws xhttp grpc h2 http; do
            domain="${network}.${type}.uicbrmo.hey.run"
            printf '  - name: %s-%s\n' "$type" "$network"
            printf '    type: %s\n' "$type"
            printf '    server: %s\n' "$domain"
            printf '    port: 443\n    tls: true\n'
            printf '    servername: %s\n' "$domain"
            printf '    network: %s\n' "$network"
            printf '    headers:\n      Host: %s\n' "$domain"
        done
    done
} >"$OPENCLASH_CONFIG"

update_openclash

test "$(grep -F -c 'server: 104.16.1.1' "$OPENCLASH_CONFIG")" -eq 15
test "$(grep -F -c 'servername:' "$OPENCLASH_CONFIG")" -eq 15
test "$(grep -F -c 'Host:' "$OPENCLASH_CONFIG")" -ge 15
test "$(grep -F -c '[CF-1]' "$OPENCLASH_CONFIG")" -eq 15
test "$(find "$tmp_dir" -name 'clash-proxies.yaml.bak.*' | wc -l | tr -d ' ')" -eq 1

printf 'openclash protocol matrix passed\n'
