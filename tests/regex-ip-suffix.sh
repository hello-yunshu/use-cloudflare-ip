#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=cf-openwrt-auto.sh
. "$repo_dir/cf-openwrt-auto.sh"

restart_service() { :; }

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# ===== Test passwall_base_name =====
[[ "$(passwall_base_name "Node [CF-1]")" == "Node" ]] || fail "passwall_base_name: default suffix"
[[ "$(passwall_base_name "Node [CF-1]-1.2.3.4")" == "Node" ]] || fail "passwall_base_name: {ip} suffix"
[[ "$(passwall_base_name "Node")" == "Node" ]] || fail "passwall_base_name: no suffix"
[[ "$(passwall_base_name "Node [CF-1] [CF-1]")" == "Node" ]] || fail "passwall_base_name: accumulated suffix"

# ===== Test openclash_base_name with {ip} =====
[[ "$(openclash_base_name "VLESS-ws [CF-1]")" == "VLESS-ws" ]] || fail "openclash_base_name: default suffix"
[[ "$(openclash_base_name "VLESS-ws [CF-1]-1.2.3.4")" == "VLESS-ws" ]] || fail "openclash_base_name: {ip} suffix"
[[ "$(openclash_base_name "VLESS-ws")" == "VLESS-ws" ]] || fail "openclash_base_name: no suffix"

# ===== Test openclash_generated_index with {ip} =====
[[ "$(openclash_generated_index "VLESS-ws [CF-1]")" == "1" ]] || fail "openclash_generated_index: default suffix"
[[ "$(openclash_generated_index "VLESS-ws [CF-1]-1.2.3.4")" == "1" ]] || fail "openclash_generated_index: {ip} suffix"
openclash_generated_index "VLESS-ws" && fail "openclash_generated_index: should fail for no suffix"
[[ "$(openclash_generated_index "VLESS-ws [CF-2]-5.6.7.8")" == "2" ]] || fail "openclash_generated_index: CF-2 with {ip}"

# ===== Test OpenClash with {ip} suffix =====
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

OPENCLASH_CONFIG="$tmp_dir/clash-proxies.yaml"
OPENCLASH_TARGET_DOMAIN="uicbrmo.hey.run"
OPENCLASH_TRANSPORT_FILTER=""
OPENCLASH_NAME_SUFFIX=" [CF-{n}]-{ip}"
FAST_IPS=("172.64.53.65" "172.64.229.52")
IP_COUNT=2
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
YAML

update_openclash

# Should generate 2 variants with {ip} in name
grep -q 'name: VLESS-ws \[CF-1\]-172.64.53.65' "$OPENCLASH_CONFIG" || fail "CF-1 with {ip} should be generated"
grep -q 'name: VLESS-ws \[CF-2\]-172.64.229.52' "$OPENCLASH_CONFIG" || fail "CF-2 with {ip} should be generated"
grep -q 'server: 172.64.53.65' "$OPENCLASH_CONFIG" || fail "CF-1 server should be updated"
grep -q 'server: 172.64.229.52' "$OPENCLASH_CONFIG" || fail "CF-2 server should be updated"

# ===== Test re-run doesn't accumulate suffix =====
update_openclash

# After re-run, names should still have exactly one [CF-N]-ip suffix
[[ "$(grep -F -c 'name: VLESS-ws [CF-' "$OPENCLASH_CONFIG")" == "2" ]] || fail "re-run should not accumulate suffixes"
grep -q 'name: VLESS-ws \[CF-1\]-172.64.53.65' "$OPENCLASH_CONFIG" || fail "CF-1 with {ip} should be preserved after re-run"
grep -q 'name: VLESS-ws \[CF-2\]-172.64.229.52' "$OPENCLASH_CONFIG" || fail "CF-2 with {ip} should be preserved after re-run"

printf 'ok regex and {ip} suffix tests\n'
