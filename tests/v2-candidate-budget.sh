#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
python3 - "$TMP/records.json" "$TMP/history.json" <<'PY'
import json,sys
records=[]
for i in range(1,620):
    records.append({'kind':'ip','value':f'104.17.{i//250}.{i%250+1}','family':'ipv4','sourceId':'community','sourceClass':'community','stale':False})
records.append({'kind':'cidr','value':'104.16.0.0/13','family':'ipv4','sourceId':'official','sourceClass':'official','stale':False})
h=[{'ip':f'104.18.0.{i}','family':'ipv4','wins':9,'lastSeen':10000-i} for i in range(1,100)]
json.dump(records,open(sys.argv[1],'w')); json.dump(h,open(sys.argv[2],'w'))
PY
for b in 100 128 256 512; do
  cfip_schedule_family ipv4 "$b" "$TMP/records.json" "$TMP/history.json" "$TMP/out.json"
  test "$(jq length "$TMP/out.json")" -eq "$b"
  test "$(jq '[.[].ip]|unique|length' "$TMP/out.json")" -eq "$b"
  test "$(jq '[.[]|select(.origin=="community")]|length' "$TMP/out.json")" -gt 0
done
echo 'v2 candidate budget contract passed'
