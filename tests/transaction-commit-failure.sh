#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runtime" "$TMP/status"
cat >"$TMP/passwall.uci" <<'EOF_UCI'
passwall.s1.address='cdn.example.com'
passwall.s1.remarks='Node A'
EOF_UCI
cat >"$TMP/managed.json" <<'EOF_STATE'
{"schemaVersion":1,"sections":[{"section":"s1","domain":"cdn.example.com","baseRemarks":"Node A","lastAddress":"cdn.example.com","lastRemarks":"Node A"}]}
EOF_STATE
cp "$TMP/passwall.uci" "$TMP/passwall.before"
cp "$TMP/managed.json" "$TMP/managed.before"
cat >"$TMP/bin/uci" <<'EOF_UCI_BIN'
#!/usr/bin/env bash
set -euo pipefail
state="${UCI_FAKE_STATE:?}"
[[ "${1:-}" == -q ]] && shift
case "${1:-}" in
  export) cat "$state" ;;
  import) cat >"$state" ;;
  revert|commit) cat >/dev/null || true ;;
  get) key="${2#passwall.}"; section="${key%%.*}"; field="${key#*.}"; sed -n "s/^passwall\.${section}\.${field}=//p" "$state" | head -1 | sed "s/^'//;s/'$//" ;;
  set) pair="$2"; path="${pair%%=*}"; value="${pair#*=}"; awk -v p="$path" -v v="$value" 'BEGIN{done=0} {k=$0; sub(/=.*/,"",k); if(k==p){print k "=\x27" v "\x27"; done=1} else print} END{if(!done) print p "=\x27" v "\x27"}' "$state" >"$state.next"; mv "$state.next" "$state" ;;
  *) exit 1 ;;
esac
EOF_UCI_BIN
chmod +x "$TMP/bin/uci"
export PATH="$TMP/bin:$PATH" UCI_FAKE_STATE="$TMP/passwall.uci" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LOG_FILE="$TMP/log"
export CFIP_RUN_ID=commit-failure CFIP_PASSWALL_STATE_FILE="$TMP/managed.json" CFIP_PASSWALL_TARGET_DOMAIN=cdn.example.com CFIP_PASSWALL_NAME_SUFFIX=' [CF-{n}]'
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"
cfip_restart_service(){ return 0; }
cat >"$TMP/selected.json" <<'EOF_SELECTED'
[{"ip":"104.16.1.1","family":"ipv4"}]
EOF_SELECTED
cfip_txn_prepare passwall
cfip_txn_apply passwall "$TMP/selected.json"
test -f "$CFIP_TXN_DIR/passwall-managed.json.pending"
mv() {
    if [[ "${2:-}" == "$CFIP_PASSWALL_STATE_FILE" && "${1:-}" == *.pending ]]; then return 1; fi
    command mv "$@"
}
rc=0; cfip_txn_commit || rc=$?
test "$rc" -ne 0
cfip_txn_rollback passwall
cmp -s "$TMP/passwall.uci" "$TMP/passwall.before"
cmp -s "$TMP/managed.json" "$TMP/managed.before"
test "$CFIP_TXN_ROLLED_BACK" = true
echo 'transaction commit failure rollback behavior passed'
