#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/status" "$TMP/runtime" "$TMP/cache"
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_SOURCE_RUNTIME_DIR="$TMP/runtime/sources" CFIP_SOURCE_CACHE_DIR="$TMP/cache" CFIP_TEST_CURL_ARGS="$TMP/curl-args" CFIP_SOURCE_CURL_MAX_FILESIZE_SUPPORTED=true
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"

cat >"$TMP/remote.txt" <<'EOF'
104.16.1.1
104.16.1.2
EOF
curl() {
    printf '%s\n' "$*" >"$CFIP_TEST_CURL_ARGS"
    local out="" previous="" arg
    for arg in "$@"; do
        [[ "$previous" == -o ]] && out="$arg"
        previous="$arg"
    done
    cp "$TMP/remote.txt" "$out"
}
export -f curl

cfip_source_fetch_remote size-cap https://example.test/ips.txt ip-text ipv4 community "$TMP/records.json"
grep -q -- '--max-filesize 524288' "$CFIP_TEST_CURL_ARGS"
test "$(jq 'length' "$TMP/records.json")" -eq 2
echo 'source download size cap contract passed'
