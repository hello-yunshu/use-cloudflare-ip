#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFIP_STATUS_DIR="$TMP/status"; CFIP_RUNTIME_DIR="$TMP/runtime"; CFIP_RUN_HISTORY="$TMP/run-history.ndjson"; CFIP_LOG_FILE="$TMP/log"; CFIP_IP_TYPE=both; CFIP_WORK_DIR="$TMP/work"; mkdir -p "$CFIP_WORK_DIR/cfst"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"

cat >"$TMP/mixed.txt" <<'DATA'
104.16.1.1
104.16.1.2:8443#HK
[2606:4700::1]:443#v6
shopify.com:443#domain
104.16.0.0/24
bad
DATA
cfip_parse_source_file "$TMP/mixed.txt" ip-text fixture community auto false "$TMP/parsed.json"
test "$(jq '.parsedCount' "$TMP/parsed.json")" -eq 4
test "$(jq '.rejectedCount' "$TMP/parsed.json")" -eq 2
jq -e '.records|map(select(.kind=="ip")|.value)|index("104.16.1.2")!=null' "$TMP/parsed.json" >/dev/null
jq -e '.records|map(.value)|index("shopify.com")==null' "$TMP/parsed.json" >/dev/null

cat >"$TMP/private.txt" <<'DATA'
10.0.0.1
192.168.1.1
127.0.0.1
169.254.1.1
fc00::1
fe80::1
2001:db8::1
104.16.1.3
DATA
cfip_parse_source_file "$TMP/private.txt" ip-text public-fixture community auto false "$TMP/public.json"
test "$(jq '.parsedCount' "$TMP/public.json")" -eq 1
test "$(jq -r '.records[0].value' "$TMP/public.json")" = 104.16.1.3

v4="$(cfip_sample_ipv4_cidr 104.16.0.0/13)"; cfip_is_ipv4 "$v4"
v6="$(cfip_sample_ipv6_cidr 2606:4700::/32)"; [[ "$v6" == 2606:4700:* ]]

python3 - <<'PY' "$TMP/records.json" "$TMP/history.json"
import json,sys
r=[]
for i in range(1,401):
    ip=f'104.16.{i//250}.{i%250+1}'
    r.append({'kind':'ip','value':ip,'family':'ipv4','sourceId':'community-a','sourceClass':'community','stale':False})
    if i%4==0:r.append({'kind':'ip','value':ip,'family':'ipv4','sourceId':'community-b','sourceClass':'community','stale':False})
r.append({'kind':'cidr','value':'104.16.0.0/13','family':'ipv4','sourceId':'official','sourceClass':'official','stale':False})
json.dump(r,open(sys.argv[1],'w'))
h=[{'ip':f'104.23.0.{i}','family':'ipv4','wins':10-i%4,'lastSeen':10000-i} for i in range(1,90)]
json.dump(h,open(sys.argv[2],'w'))
PY
for budget in 100 128 256 512; do
  CFIP_RUN_HISTORY="$TMP/no-history-file" cfip_schedule_family ipv4 "$budget" "$TMP/records.json" "$TMP/history.json" "$TMP/scheduled-$budget.json"
  test "$(jq 'length' "$TMP/scheduled-$budget.json")" -eq "$budget"
  h=$((budget/8)); o=$((budget/4)); c=$((budget-h-o))
  test "$(jq '[.[]|select(.origin=="history")]|length' "$TMP/scheduled-$budget.json")" -eq "$h"
  test "$(jq '[.[]|select(.origin=="community")]|length' "$TMP/scheduled-$budget.json")" -eq "$c"
  test "$(jq '[.[]|select(.origin=="range-explore")]|length' "$TMP/scheduled-$budget.json")" -eq "$o"
  test "$(jq '[.[].ip]|unique|length' "$TMP/scheduled-$budget.json")" -eq "$budget"
done


# With no local history yet, its unused quota flows to community first, keeping official exploration at ~25%.
printf '[]' >"$TMP/empty-history.json"
CFIP_RUN_HISTORY="$TMP/no-history-file" cfip_schedule_family ipv4 128 "$TMP/records.json" "$TMP/empty-history.json" "$TMP/nohist.json"
test "$(jq '[.[]|select(.origin=="community")]|length' "$TMP/nohist.json")" -eq 96
test "$(jq '[.[]|select(.origin=="range-explore")]|length' "$TMP/nohist.json")" -eq 32

# last-good cache: a failed refresh must reuse validated cached content and mark it stale.
cat >"$TMP/remote.txt" <<'DATA'
104.18.1.1
104.18.1.2:8443#seed
DATA
curl(){ local out="" prev="" a; for a in "$@"; do [[ "$prev" == -o ]] && out="$a"; prev="$a"; done; cp "$TMP/remote.txt" "$out"; }
export -f curl
cfip_source_fetch_remote cache-test https://example.test/ip.txt ip-text ipv4 community "$TMP/fresh.json"
test "$(jq 'length' "$TMP/fresh.json")" -eq 2
jq -e '.stale==false and .fromCache==false' "$CFIP_SOURCE_RUNTIME_DIR/cache-test/metadata.json" >/dev/null
curl(){ return 22; }
export -f curl
cfip_source_fetch_remote cache-test https://example.test/ip.txt ip-text ipv4 community "$TMP/stale.json"
test "$(jq 'length' "$TMP/stale.json")" -eq 2
jq -e '.stale==true and .fromCache==true and .lastError=="fetch_failed"' "$CFIP_SOURCE_RUNTIME_DIR/cache-test/metadata.json" >/dev/null

# A syntactically valid but too-small refresh must not poison the last-good cache.
cat >"$TMP/remote.txt" <<'DATA'
104.18.9.9
DATA
curl(){ local out="" prev="" a; for a in "$@"; do [[ "$prev" == -o ]] && out="$a"; prev="$a"; done; cp "$TMP/remote.txt" "$out"; }
export -f curl
cfip_source_fetch_remote cache-test https://example.test/ip.txt ip-text ipv4 community "$TMP/too-small.json"
test "$(jq 'length' "$TMP/too-small.json")" -eq 2
jq -e '.stale==true and .fromCache==true and .lastError=="too_few_valid_candidates"' "$CFIP_SOURCE_RUNTIME_DIR/cache-test/metadata.json" >/dev/null

echo 'v2 source engine tests passed'

# Dual-stack preparation must still produce one bounded, explicit-IP CFST input file.
python3 - <<'PY' "$TMP/dual-records.json" "$TMP/dual-history.json"
import json,sys
records=[]
for i in range(1,260):
    records.append({'kind':'ip','value':f'104.20.{i//250}.{i%250+1}','family':'ipv4','sourceId':'community-v4','sourceClass':'community','stale':False})
for i in range(1,140):
    records.append({'kind':'ip','value':f'2606:4700:100::{i:x}','family':'ipv6','sourceId':'community-v6','sourceClass':'community','stale':False})
records += [
    {'kind':'cidr','value':'104.16.0.0/13','family':'ipv4','sourceId':'official-v4','sourceClass':'official','stale':False},
    {'kind':'cidr','value':'2606:4700::/32','family':'ipv6','sourceId':'official-v6','sourceClass':'official','stale':False},
]
json.dump(records,open(sys.argv[1],'w'))
h=[]
for i in range(1,50): h.append({'ip':f'104.30.0.{i}','family':'ipv4','wins':8,'lastSeen':1000-i})
for i in range(1,30): h.append({'ip':f'2606:4700:200::{i:x}','family':'ipv6','wins':8,'lastSeen':1000-i})
json.dump(h,open(sys.argv[2],'w'))
PY
cfip_collect_enabled_sources(){ cp "$TMP/dual-records.json" "$1"; printf '[]\n' >"$2"; }
cfip_history_pool_json(){ cp "$TMP/dual-history.json" "$1"; }
CFIP_IP_TYPE=both CFIP_CANDIDATE_BUDGET=128 CFIP_BUILTIN_SOURCES='' cfip_prepare_candidate_pool "$TMP/dual-pool.json" "$TMP/dual-input.txt" "$TMP/dual-status.json"
test "$(jq 'length' "$TMP/dual-pool.json")" -eq 128
test "$(jq '[.[]|select(.family=="ipv4")]|length' "$TMP/dual-pool.json")" -eq 96
test "$(jq '[.[]|select(.family=="ipv6")]|length' "$TMP/dual-pool.json")" -eq 32
test "$(wc -l < "$TMP/dual-input.txt")" -eq 128
! grep -Ev '(^([0-9]{1,3}\.){3}[0-9]{1,3}/32$)|(^[0-9A-Fa-f:]+/128$)' "$TMP/dual-input.txt" | grep -q .

# The portable measurement watchdog must fail closed with the conventional timeout status.
set +e
cfip_run_with_timeout 1 bash -c 'sleep 2'
timeout_rc=$?
set -e
test "$timeout_rc" -eq 124
