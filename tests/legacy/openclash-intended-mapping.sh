#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
source "$PKG/root/usr/libexec/cf-ip/openclash-readback.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"}]' >"$TMP/selected.json"
cat >"$TMP/config.yaml" <<'YAML'
proxies:
  - name: Node [CF-1]
    server: 104.16.1.1
    servername: cdn.example.com
    network: xhttp
    xhttp-opts:
      headers:
        Host: cdn.example.com
YAML
cfip_openclash_readback_intended "$TMP/selected.json" "$TMP/config.yaml" cdn.example.com ' [CF-{n}]'
echo 'OpenClash IntendedMappingV1 readback passed'
