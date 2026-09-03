#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runtime" "$TMP/status"
cat >"$TMP/passwall.state" <<'EOF'
passwall.s1.address='cdn.example.com'
passwall.s1.remarks='Node A'
passwall.s2.address='other.example.com'
passwall.s2.remarks='Node B'
EOF
cat >"$TMP/bin/uci" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${UCI_FAKE_STATE:?}"
[[ "${1:-}" == -q ]] && shift
case "${1:-}" in
  show) cat "$state" ;;
  get) key="$2"; key="${key#passwall.}"; section="${key%%.*}"; field="${key#*.}"; sed -n "s/^passwall\.${section}\.${field}=//p" "$state" | head -1 | sed "s/^'//;s/'$//" ;;
  set) pair="$2"; path="${pair%%=*}"; value="${pair#*=}"; tmp="${state}.next"; awk -v p="$path" -v v="$value" 'BEGIN{done=0} {key=$0; sub(/=.*/,"",key); if(key==p){print key "=\x27" v "\x27"; done=1} else print} END{if(!done) print p "=\x27" v "\x27"}' "$state" >"$tmp"; mv "$tmp" "$state" ;;
  commit|revert|import) cat >/dev/null || true ;;
  export) cat "$state" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/uci"
export PATH="$TMP/bin:$PATH" UCI_FAKE_STATE="$TMP/passwall.state"
export CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LOG_FILE="$TMP/log"
export CFIP_PASSWALL_TARGET_DOMAIN='cdn.example.com,other.example.com' CFIP_PASSWALL_NAME_SUFFIX=' [CF-{n}]'
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"
cfip_restart_service(){ return 0; }
cat >"$TMP/selected.json" <<'JSON'
[{"ip":"104.16.1.1","family":"ipv4"},{"ip":"104.16.1.2","family":"ipv4"}]
JSON
CFIP_PASSWALL_STATE_FILE="$TMP/passwall-managed.json"
cfip_passwall_apply_selected "$TMP/selected.json"
grep -q "passwall.s1.address='104.16.1.1'" "$TMP/passwall.state"
grep -q "passwall.s2.address='104.16.1.2'" "$TMP/passwall.state"
jq -e '.sections|length==2' "$TMP/passwall-managed.json" >/dev/null
cfip_passwall_apply_selected "$TMP/selected.json"
if grep -q '\[CF-.*\].*\[CF-' "$TMP/passwall.state"; then
  echo 'PassWall suffix duplicated on rerun' >&2
  exit 1
fi
awk '{if ($0 ~ /^passwall\.s1\.address=/) print "passwall.s1.address=\x271.1.1.1\x27"; else print}' "$TMP/passwall.state" >"$TMP/passwall.state.next"
mv "$TMP/passwall.state.next" "$TMP/passwall.state"
if cfip_passwall_apply_selected "$TMP/selected.json"; then echo 'user edit conflict unexpectedly accepted' >&2; exit 1; fi
echo 'PassWall managed ownership contract passed'
