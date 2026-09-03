#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if ! command -v setsid >/dev/null 2>&1 && [[ ! -r /proc/self/task/$$/children ]]; then
  echo 'signal child-tree rollback contract skipped: no process-group or child-tree primitive'
  exit 0
fi
mkdir -p "$TMP/bin" "$TMP/runtime" "$TMP/status"
cat >"$TMP/bin/uci" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${UCI_FAKE_STATE:?}"
[[ "${1:-}" == -q ]] && shift
case "${1:-}" in
  export|show) cat "$state" ;;
  import) cat >"$state" ;;
  set) pair="$2"; key="${pair%%=*}"; value="${pair#*=}"; sed "s#^${key}=.*#${key}='${value}'#" "$state" >"$state.next"; mv "$state.next" "$state" ;;
  commit|revert) cat >/dev/null || true ;;
  get) exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/uci"
printf "passwall.s1.address='original.example'\n" >"$TMP/passwall.uci"
export PATH="$TMP/bin:$PATH" UCI_FAKE_STATE="$TMP/passwall.uci" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LOG_FILE="$TMP/log" CFIP_RUN_ID=signal-tree CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_DISABLE_SETSID=false CFIP_TIMEOUT_GRACE_SECONDS=0
export ROOT RACE_FILE="$TMP/race"
set +e
bash -c '
  source "$CFIP_LIB_DIR/common.sh"
  source "$CFIP_LIB_DIR/transaction.sh"
  cfip_txn_prepare passwall
  uci set passwall.s1.address=mutated.example
  uci commit passwall
  trap "cfip_cancel_active_operation; cfip_txn_rollback passwall; exit 143" INT TERM
  cfip_run_with_timeout 10 bash -c '\''printf stage-1 >"$1"; : >"$2"; (sleep 3; printf stage-2 >>"$1") & wait'\'' bash "$RACE_FILE" "$RACE_FILE.ready"
' &
pid=$!
for i in {1..50}; do [[ -f "$RACE_FILE.ready" ]] && break; /bin/sleep 0.1; done
test -f "$RACE_FILE.ready"
kill -TERM "$pid"
wait "$pid"
rc=$?
set -e
test "$rc" -eq 143
test "$(cat "$TMP/passwall.uci")" = "passwall.s1.address='original.example'"
/bin/sleep 4
test "$(cat "$RACE_FILE")" = stage-1
echo 'signal child-tree rollback contract passed'
