#!/usr/bin/env bash

set -Eeuo pipefail

repo_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
. "$repo_dir/cf-openwrt-auto.sh"

restart_service() {
	:
}

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

[[ "$(lower TRUE)" == "true" ]] || fail "lower TRUE should be true"
[[ "$(lower xhttp)" == "xhttp" ]] || fail "lower xhttp should stay xhttp"

OPENCLASH_CONFIG="$tmp_dir/clash-proxies.yaml"
OPENCLASH_TARGET_DOMAIN="uicbrmo.hey.run"
OPENCLASH_TRANSPORT_FILTER="xhttp"
OPENCLASH_NAME_SUFFIX=" [CF-{n}]"
FAST_IPS=("172.64.53.65" "172.64.229.52" "162.159.33.150" "162.159.39.96")
IP_COUNT=4
VERBOSE=true

cat >"$OPENCLASH_CONFIG" <<'YAML'
proxies:
  - name: VLESS-ws
    type: vless
    server: uicbrmo.hey.run
    port: 443
    tls: true
    network: ws
    ws-opts:
      path: /ws
  - name: VLESS-xhttp
    type: vless
    server: uicbrmo.hey.run
    port: 443
    tls: true
    network: xhttp
    xhttp-opts:
      path: /xhttp
YAML

update_openclash

grep -q 'server: 172.64.53.65' "$OPENCLASH_CONFIG" || fail "xhttp proxy was not updated"
grep -q 'server: 172.64.229.52' "$OPENCLASH_CONFIG" || fail "xhttp CF-2 proxy was not generated"
grep -q 'server: 162.159.33.150' "$OPENCLASH_CONFIG" || fail "xhttp CF-3 proxy was not generated"
grep -q 'server: 162.159.39.96' "$OPENCLASH_CONFIG" || fail "xhttp CF-4 proxy was not generated"
[[ "$(grep -F -c 'name: VLESS-xhttp [CF-' "$OPENCLASH_CONFIG")" == "4" ]] || fail "xhttp proxy should be expanded to four marked proxies"
grep -q 'server: uicbrmo.hey.run' "$OPENCLASH_CONFIG" || fail "ws proxy should stay unchanged"
[[ "$(grep -c 'servername: uicbrmo.hey.run' "$OPENCLASH_CONFIG")" == "4" ]] || fail "servername should stay as the domain on all generated proxies"
[[ "$(grep -c 'Host: uicbrmo.hey.run' "$OPENCLASH_CONFIG")" == "4" ]] || fail "xhttp Host should stay as the domain on all generated proxies"

cat >"$OPENCLASH_CONFIG" <<'YAML'
proxies:
  - name: VLESS-ws [CF-1]
    type: vless
    server: 162.159.13.39
    port: 443
    tls: true
    servername: uicbrmo.hey.run
    network: ws
    ws-opts:
      path: /ws
      headers:
        Host: uicbrmo.hey.run
  - name: VLESS-xhttp [CF-1]
    type: vless
    server: 162.159.38.42
    port: 443
    tls: true
    servername: uicbrmo.hey.run
    network: xhttp
    xhttp-opts:
      path: /xhttp
      headers:
        Host: uicbrmo.hey.run
YAML

update_openclash

grep -q 'name: VLESS-ws \[CF-1\]' "$OPENCLASH_CONFIG" || fail "ws marked proxy should stay present"
grep -q 'server: 162.159.13.39' "$OPENCLASH_CONFIG" || fail "ws marked proxy should stay unchanged under xhttp filter"
[[ "$(grep -F -c 'name: VLESS-xhttp [CF-' "$OPENCLASH_CONFIG")" == "4" ]] || fail "existing xhttp CF-1 should be expanded back to four marked proxies"
grep -q 'server: 172.64.53.65' "$OPENCLASH_CONFIG" || fail "existing xhttp CF-1 should be refreshed from selected IPs"
grep -q 'server: 172.64.229.52' "$OPENCLASH_CONFIG" || fail "missing xhttp CF-2 should be generated from marked template"
grep -q 'server: 162.159.33.150' "$OPENCLASH_CONFIG" || fail "missing xhttp CF-3 should be generated from marked template"
grep -q 'server: 162.159.39.96' "$OPENCLASH_CONFIG" || fail "missing xhttp CF-4 should be generated from marked template"

IP_COUNT=2
FAST_IPS=("104.18.1.1" "104.18.1.2")

cat >"$OPENCLASH_CONFIG" <<'YAML'
proxies:
  - name: VLESS-xhttp
    type: vless
    server: uicbrmo.hey.run
    port: 443
    tls: true
    network: xhttp
    xhttp-opts:
      path: /xhttp
YAML

update_openclash

[[ "$(grep -F -c 'name: VLESS-xhttp [CF-' "$OPENCLASH_CONFIG")" == "2" ]] || fail "initial unmarked xhttp proxy should expand to IP_COUNT marked proxies"
grep -q 'name: VLESS-xhttp \[CF-1\]' "$OPENCLASH_CONFIG" || fail "CF-1 should be generated from unmarked template"
grep -q 'name: VLESS-xhttp \[CF-2\]' "$OPENCLASH_CONFIG" || fail "CF-2 should be generated from unmarked template"
! grep -q 'name: VLESS-xhttp \[CF-3\]' "$OPENCLASH_CONFIG" || fail "proxy expansion should not exceed IP_COUNT"

printf 'ok openclash xhttp filter\n'
