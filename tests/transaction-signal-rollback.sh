#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runtime" "$TMP/status"
cat >"$TMP/bin/uci" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${UCI_FAKE_STATE:?}"; [[ "${1:-}" == -q ]] && shift
case "${1:-}" in
  export|show) cat "$state" ;;
  import) cat >"$state" ;;
  set) pair="$2"; key="${pair%%=*}"; val="${pair#*=}"; sed "s#^${key}=.*#${key}='${val}'#" "$state" >"$state.next"; mv "$state.next" "$state" ;;
  commit|revert) cat >/dev/null || true ;;
  get) exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/uci"
printf "passwall.s1.address='cdn.example.com'\n" >"$TMP/passwall.uci"
export PATH="$TMP/bin:$PATH" UCI_FAKE_STATE="$TMP/passwall.uci" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LOG_FILE="$TMP/log" CFIP_RUN_ID=signal-test CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export ROOT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"
cp "$TMP/passwall.uci" "$TMP/before"
set +e
env CFIP_TXN_ORIGINAL_RUNNING=false bash -c '
  source "$CFIP_LIB_DIR/common.sh"
  source "$CFIP_LIB_DIR/transaction.sh"
  source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
  cfip_txn_prepare passwall
  uci set passwall.s1.address=104.16.1.1
  uci commit passwall
  CFIP_TXN_STATE=MUTATED
  trap run_cleanup EXIT
  trap run_signal_cleanup INT TERM
  kill -TERM $$
'
rc=$?
set -e
test "$rc" -eq 143
cmp -s "$TMP/passwall.uci" "$TMP/before"
test -z "$(find "$TMP/runtime" -type d -name 'txn-*' -print -quit)"
echo 'transaction signal rollback contract passed'
