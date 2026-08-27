#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh"
cat >"$TMP/selected.json" <<'EOF_SELECTED'
[{"ip":"104.16.1.1","family":"ipv4"},{"ip":"104.16.1.2","family":"ipv4"}]
EOF_SELECTED
cat >"$TMP/config.yaml" <<'EOF_YAML'
proxies:
  - name: Node [CF-1]
    type: vmess
    server: 104.16.1.1
    tls: true
    servername: domain-b.example.com
    network: ws
    ws-opts:
      headers:
        Host: domain-b.example.com
  - name: Node [CF-2]
    type: vmess
    server: 104.16.1.2
    tls: true
    servername: domain-a.example.com
    network: ws
    ws-opts:
      headers:
        Host: domain-a.example.com
EOF_YAML
mkdir -p "$TMP/txn"
cat >"$TMP/txn/openclash-intended.json" <<'EOF_EXPECTED'
[{"name":"Node [CF-1]","server":"104.16.1.1","servername":"domain-a.example.com","network":"ws","host":"domain-a.example.com"},{"name":"Node [CF-2]","server":"104.16.1.2","servername":"domain-b.example.com","network":"ws","host":"domain-b.example.com"}]
EOF_EXPECTED
CFIP_TXN_DIR="$TMP/txn"
if cfip_openclash_readback_intended "$TMP/selected.json" "$TMP/config.yaml" 'domain-a.example.com,domain-b.example.com' ' [CF-{n}]'; then
    echo 'cross-wired IntendedMapping unexpectedly passed' >&2
    exit 1
fi
sed 's/network: ws/network: grpc/' "$TMP/config.yaml" >"$TMP/wrong-network.yaml"
if CFIP_TXN_DIR="$TMP/empty" cfip_openclash_readback_intended "$TMP/selected.json" "$TMP/wrong-network.yaml" 'domain-a.example.com,domain-b.example.com' ' [CF-{n}]' ws; then
    echo 'wrong-network mapping unexpectedly passed' >&2
    exit 1
fi
echo 'OpenClash IntendedMapping negative behavior passed'
