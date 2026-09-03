#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/init" "$TMP/runtime" "$TMP/status"
for service in passwall openclash; do
    cat >"$TMP/init/$service" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == running ]] && sleep 30
EOF
    chmod +x "$TMP/init/$service"
done
export CFIP_INIT_DIR="$TMP/init" CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_FILE="$TMP/status/status.json" CFIP_LOG_FILE="$TMP/log" CFIP_RUN_HISTORY="$TMP/history" CFIP_WORK_DIR="$TMP/work" CFIP_STATUS_TIMEOUT_SECONDS=1 CFIP_TIMEOUT_GRACE_SECONDS=0
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
cfip_rill_status_json(){ printf '%s\n' '{"available":false,"state":"disabled"}'; }
cfip_publisher_status_json(){ printf '%s\n' '{"state":"disabled"}'; }
CFIP_RUN_ID=status-timeout CFIP_MODE=passwall CFIP_IP_TYPE=ipv4 CFIP_SPEEDTEST_PROTOCOL=tcp CFIP_SCRIPT_VERSION=2.0.0-dev CFIP_PACKAGE_RELEASE=1 CFIP_ENABLED=false CFIP_IP_COUNT=4 CFIP_CANDIDATE_BUDGET=128 CFIP_RECOVERY_DEADLINE=0 CFIP_RECOVERY_ACTIVE=false CFIP_RECOVERY_ERROR="" ENGINE_SCHEMA_VERSION=2
started="$(date +%s)"
write_status false status success ""
elapsed=$(( $(date +%s) - started ))
test "$elapsed" -le 5
jq -e '.passwall_installed==true and .passwall_running==false and .openclash_running==false' "$CFIP_STATUS_FILE" >/dev/null
echo 'status running timeout contract passed'
