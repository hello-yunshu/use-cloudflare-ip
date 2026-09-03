#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/init"
cat >"$TMP/init/passwall" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == running ]] && sleep 30
EOF
chmod +x "$TMP/init/passwall"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
export CFIP_INIT_DIR="$TMP/init" CFIP_STATUS_TIMEOUT_SECONDS=1 CFIP_TIMEOUT_GRACE_SECONDS=0
started="$(date +%s)"
set +e
cfip_service_running passwall status
rc=$?
set -e
elapsed=$(( $(date +%s) - started ))
test "$rc" -ne 0
test "$elapsed" -le 3
echo 'service running timeout contract passed'
