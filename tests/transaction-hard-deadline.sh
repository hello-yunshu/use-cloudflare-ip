#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/init"
cat >"$TMP/init/passwall" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in running) exit 0;; stop|restart) sleep 4;; esac
EOF
chmod +x "$TMP/init/passwall"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
export CFIP_INIT_DIR="$TMP/init"
CFIP_MEASUREMENT_DEADLINE=$(( $(date +%s) + 1 )); start=$(date +%s); rc=0; cfip_stop_service passwall || rc=$?; elapsed=$(( $(date +%s)-start ))
test "$rc" -eq 124; test "$elapsed" -lt 4
CFIP_RECOVERY_DEADLINE=$(( $(date +%s) + 1 )); rc=0; cfip_restart_service passwall recovery || rc=$?
test "$rc" -eq 124
cat >"$TMP/legacy" <<'EOF'
#!/usr/bin/env bash
sleep 4
EOF
chmod +x "$TMP/legacy"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-transform.sh"
export CFIP_LEGACY_BIN="$TMP/legacy"
CFIP_MEASUREMENT_DEADLINE=$(( $(date +%s) + 1 )); rc=0; cfip_openclash_transform_selected "$TMP/legacy" || rc=$?
test "$rc" -eq 124
echo 'transaction hard-deadline contract passed'
