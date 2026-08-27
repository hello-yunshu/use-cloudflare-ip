#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/init"
cat >"$TMP/init/passwall" <<'EOF_INIT'
#!/usr/bin/env bash
case "${1:-}" in
  restart) printf 'restart\n' >>"${CFIP_TEST_LOG:?}"; exit 0 ;;
  running) exit 0 ;;
  *) exit 0 ;;
esac
EOF_INIT
chmod +x "$TMP/init/passwall"
export CFIP_INIT_DIR="$TMP/init" CFIP_TEST_LOG="$TMP/service.log" CFIP_RECOVERY_TIMEOUT=30
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
CFIP_MEASUREMENT_DEADLINE=$(( $(date +%s) - 1 ))
cfip_begin_recovery
cfip_restart_service passwall recovery
test "$(cat "$CFIP_TEST_LOG")" = restart
test "$(cfip_measurement_remaining)" -eq 0
test "$(cfip_recovery_remaining)" -gt 0
CFIP_RECOVERY_DEADLINE=$(( $(date +%s) - 1 ))
rc=0; cfip_restart_service passwall recovery || rc=$?
test "$rc" -eq 124
echo 'measurement/recovery deadline behavior passed'
