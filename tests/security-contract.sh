#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CFIP_STATUS_DIR="$TMP/status"
CFIP_RUNTIME_DIR="$TMP/runtime"
CFIP_LOG_FILE="$TMP/log"
CFIP_IP_TYPE=both
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"

for ip in \
    10.0.0.1 100.64.0.1 100.127.255.254 127.0.0.1 169.254.1.1 \
    172.16.0.1 192.168.1.1 192.0.0.1 192.0.2.1 198.18.0.1 \
    198.51.100.1 203.0.113.1 224.0.0.1 \
    :: ::1 ::ffff:c000:201 fc00::1 fd00::1 fe80::1 ff02::1 2001:db8::1; do
    ! cfip_is_public_candidate "$ip"
done

for ip in 23.0.0.1 104.16.1.1 2606:4700::1 2001:4860:4860::8888; do
    cfip_is_public_candidate "$ip"
done

cat >"$TMP/security-input.txt" <<'DATA'
100.64.0.1
100.127.255.254
23.0.0.1
::ffff:c000:201
2606:4700::1
100.64.0.0/10
2606:4700::/32
DATA
cfip_parse_source_file "$TMP/security-input.txt" ip-text security-fixture community both false "$TMP/security.json"
test "$(jq '.parsedCount' "$TMP/security.json")" -eq 3
jq -e '.records|map(.value)|index("100.64.0.1")==null and index("::ffff:c000:201")==null' "$TMP/security.json" >/dev/null

sample="$(cfip_sample_one_cidr 2606:4700::/32)"
cfip_is_public_candidate "$sample"
! cfip_sample_one_cidr 100.64.0.0/10 >/dev/null

cfip_valid_cron '*/15 0-6 * * 1-5'
cfip_valid_cron '0 0 1,15 * *'
! cfip_valid_cron '0 0 * * *;id'
! cfip_valid_cron '0 0 * * * extra'
! cfip_valid_cron $'0 0 * * *\n/etc/passwd'
cfip_https_url_or_empty ''
cfip_https_url_or_empty 'https://example.com/path'
! cfip_https_url_or_empty 'http://example.com/path'
! cfip_https_url_or_empty 'https://example.com/path with-space'

echo 'security contract passed'
