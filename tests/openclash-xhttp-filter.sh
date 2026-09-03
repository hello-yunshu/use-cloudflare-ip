#!/usr/bin/env bash
# shellcheck disable=SC2034

set -Eeuo pipefail

repo_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=cf-openwrt-auto.sh
. "$repo_dir/cf-openwrt-auto.sh"

restart_service() {
	:
}

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_blank_before() {
	local pattern="$1" file="$2"

	awk -v pattern="$pattern" '
		index($0, pattern) {
			if (NR == 1 || previous != "") {
				exit 1
			}
			found = 1
		}
		{ previous = $0 }
		END { if (!found) exit 2 }
	' "$file" || fail "expected a blank line before: $pattern"
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
assert_blank_before '  - name: VLESS-xhttp [CF-1]' "$OPENCLASH_CONFIG"
assert_blank_before '  - name: VLESS-xhttp [CF-2]' "$OPENCLASH_CONFIG"
assert_blank_before '  - name: VLESS-xhttp [CF-3]' "$OPENCLASH_CONFIG"
assert_blank_before '  - name: VLESS-xhttp [CF-4]' "$OPENCLASH_CONFIG"
grep -q 'server: uicbrmo.hey.run' "$OPENCLASH_CONFIG" || fail "ws proxy should stay unchanged"
[[ "$(grep -c 'servername: uicbrmo.hey.run' "$OPENCLASH_CONFIG")" == "4" ]] || fail "servername should stay as the domain on all generated proxies"
[[ "$(grep -c 'Host: uicbrmo.hey.run' "$OPENCLASH_CONFIG")" == "4" ]] || fail "xhttp Host should stay as the domain on all generated proxies"
[[ "$(find "$tmp_dir" -name 'clash-proxies.yaml.bak.*' | wc -l | tr -d ' ')" == "1" ]] || fail "successful update should create one backup"
grep -q 'server: uicbrmo.hey.run' "$(find "$tmp_dir" -name 'clash-proxies.yaml.bak.*' | head -n 1)" || fail "backup should contain the pre-update config"

rm -f "$tmp_dir"/no-match.yaml.bak.*
OPENCLASH_CONFIG="$tmp_dir/no-match.yaml"
cat >"$OPENCLASH_CONFIG" <<'YAML'
proxies:
  - name: VLESS-xhttp
    type: vless
    server: no-match.example.com
    port: 443
    tls: true
    network: xhttp
YAML

if ( update_openclash ) 2>/dev/null; then
	fail "OpenClash update should fail when no proxy matches target domain"
fi
if compgen -G "$tmp_dir/no-match.yaml.bak.*" >/dev/null; then
	fail "failed update should not create a backup"
fi

OPENCLASH_CONFIG="$tmp_dir/clash-proxies.yaml"
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
assert_blank_before '  - name: VLESS-xhttp [CF-2]' "$OPENCLASH_CONFIG"
if grep -q 'name: VLESS-xhttp \[CF-3\]' "$OPENCLASH_CONFIG"; then
    fail "proxy expansion should not exceed IP_COUNT"
fi

printf 'ok openclash xhttp filter\n'
