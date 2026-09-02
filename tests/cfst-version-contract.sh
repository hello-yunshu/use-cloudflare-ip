#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_WORK_DIR="$TMP/work"
mkdir -p "$CFIP_WORK_DIR/cfst"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/cfst.sh"
cat >"$CFIP_WORK_DIR/cfst/cfst" <<'EOF_CFST'
#!/usr/bin/env bash
printf 'CloudflareSpeedTest v2.3.5\n'
EOF_CFST
chmod +x "$CFIP_WORK_DIR/cfst/cfst"
test "$(cfip_cfst_version "$CFIP_WORK_DIR/cfst/cfst")" = v2.3.5
printf '%s\n' '2.3.6' >"$CFIP_WORK_DIR/cfst/cfst_version.txt"
test "$(cfip_cfst_version "$CFIP_WORK_DIR/cfst/cfst")" = 2.3.6
printf '%s\n' 'unknown' >"$CFIP_WORK_DIR/cfst/cfst_version.txt"
test "$(cfip_cfst_version "$CFIP_WORK_DIR/cfst/cfst")" = v2.3.5
printf '%s\n' 'no version here' >"$CFIP_WORK_DIR/cfst/cfst_version.txt"
cat >"$CFIP_WORK_DIR/cfst/cfst" <<'EOF_UNKNOWN'
#!/usr/bin/env bash
printf 'CloudflareSpeedTest unknown\n'
EOF_UNKNOWN
chmod +x "$CFIP_WORK_DIR/cfst/cfst"
if cfip_cfst_version "$CFIP_WORK_DIR/cfst/cfst" >/dev/null 2>&1; then exit 1; fi
echo 'CFST version detection contract passed'
