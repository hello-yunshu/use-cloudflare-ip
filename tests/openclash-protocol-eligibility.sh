#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh"
printf '[{"ip":"104.16.1.1","family":"ipv4"}]\n' >"$TMP/selected.json"
for spec in 'vless ws' 'vmess xhttp' 'trojan grpc' 'vless h2' 'vmess http'; do
    set -- $spec; type="$1"; network="$2"; domain="$type-$network.example.com"
    cat >"$TMP/config.yaml" <<EOF
proxies:
  - name: $type-$network
    type: $type
    server: $domain
    tls: false
    servername: $domain
    network: $network
EOF
    cfip_openclash_intended_from_templates "$TMP/selected.json" "$TMP/config.yaml" "$domain" ' [CF-{n}]' '' "$TMP/intended.json"
    test "$(jq length "$TMP/intended.json")" -eq 1
done
! cfip_openclash_protocol_supported shadowsocks false ws
! cfip_openclash_protocol_supported vless false tcp
echo 'OpenClash canonical eligibility contract passed'
