#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/cfst"
cat >"$TMP/cfst/cfst" <<'CFST'
#!/usr/bin/env bash
set -euo pipefail
: "${CFST_COUNT_FILE:?}"; : "${CFST_FIXTURE:?}"
echo x >>"$CFST_COUNT_FILE"
out=""
while (($#)); do [[ "$1" == -o ]] && { shift; out="$1"; }; shift; done
cp "$CFST_FIXTURE" "$out"
CFST
chmod +x "$TMP/cfst/cfst"
export CFST_COUNT_FILE="$TMP/count" CFST_FIXTURE="$ROOT/tests/fixtures/cfst/mixed-normal.csv"
CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_WORK_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LOG_FILE="$TMP/log" bash -c '
  source "$1/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
  CFIP_WORK_DIR="$2"; CFIP_RUNTIME_DIR="$2/runtime"; CFIP_STATUS_DIR="$2/status"; CFIP_LOG_FILE="$2/log"; mkdir -p "$CFIP_RUNTIME_DIR"
  CFIP_RUN_ID=test; CFIP_SPEEDTEST_PROTOCOL=tcp; CFIP_SPEEDTEST_THREADS=20; CFIP_SPEEDTEST_PING_COUNT=2; CFIP_SPEEDTEST_DN=2; CFIP_SPEEDTEST_DT=2; CFIP_SPEEDTEST_TLL=0; CFIP_SPEEDTEST_TL=""; CFIP_PROBE_TOP_COUNT=3; CFIP_MONOTONIC_SECONDS=100; CFIP_MEASUREMENT_DEADLINE=120
  CFIP_CANDIDATE_INPUT_FILE="$2/input.txt"; CFIP_INPUT_POOL_FILE="$2/pool.json"; CFIP_CANDIDATES_FILE="$2/candidates.json"
  cat >"$CFIP_CANDIDATE_INPUT_FILE" <<DATA
104.16.1.1/32
2606:4700::1111/128
104.16.1.2/32
DATA
  cat >"$CFIP_INPUT_POOL_FILE" <<JSON
[{"ip":"104.16.1.1","family":"ipv4","origin":"community","sources":["s1"],"sourceCount":1,"stale":false},{"ip":"2606:4700::1111","family":"ipv6","origin":"range-explore","sources":["cidr:v6"],"sourceCount":0,"stale":false},{"ip":"104.16.1.2","family":"ipv4","origin":"history","sources":["local-history"],"sourceCount":0,"stale":false}]
JSON
  run_cfst
  test "$(jq length "$CFIP_CANDIDATES_FILE")" -eq 3
  jq -e '"'"'.[0].origin=="community" and .[1].family=="ipv6" and .[2].origin=="history"'"'"' "$CFIP_CANDIDATES_FILE" >/dev/null
' _ "$ROOT" "$TMP"
test "$(wc -l <"$TMP/count")" -eq 1
echo 'v2 single-CFST contract test passed'
