#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/init" "$TMP/runtime"
cat >"$TMP/init/passwall" <<'EOF_INIT'
#!/usr/bin/env bash
printf '%s\n' "${1:-}" >>"${CFIP_SERVICE_LOG:?}"
case "${1:-}" in running|restart) exit 0 ;; *) exit 0 ;; esac
EOF_INIT
chmod +x "$TMP/init/passwall"
cat >"$TMP/bin/uci" <<'EOF_UCI'
#!/usr/bin/env bash
set -euo pipefail
state="${UCI_FAKE_STATE:?}"
if [[ "${1:-}" == -q ]]; then shift; fi
case "${1:-}" in
  get)
    case "$2" in
      cf_ip.main.enabled) printf '0' ;; cf_ip.main.mode) printf 'passwall' ;; cf_ip.main.ip_count) printf '1' ;;
      cf_ip.main.ip_type) printf 'ipv4' ;; cf_ip.main.speedtest_protocol) printf 'tcp' ;; cf_ip.main.speedtest_dn) printf '8' ;;
      cf_ip.main.speedtest_dt) printf '6' ;; cf_ip.main.speedtest_tll) printf '40' ;; cf_ip.main.speedtest_threads) printf '20' ;;
      cf_ip.main.speedtest_ping_count) printf '1' ;; cf_ip.main.stop_service) printf '1' ;; cf_ip.main.work_dir) printf '%s' "$UCI_WORK_DIR" ;;
      cf_ip.main.candidate_budget) printf '128' ;; cf_ip.main.probe_top_count) printf '1' ;; cf_ip.main.probe_concurrency) printf '1' ;;
      cf_ip.main.probe_timeout) printf '5' ;; cf_ip.main.measurement_timeout) printf '60' ;; cf_ip.main.recovery_timeout) printf '30' ;;
      cf_ip.main.builtin_sources) printf 'cloudflare-official-v4' ;; cf_ip.main.verbose) printf '0' ;;
      cf_ip.passwall.target_domain) printf 'cdn.example.com' ;; cf_ip.passwall.name_suffix) printf ' [CF-{n}]' ;;
      passwall.*) key="${2#passwall.}"; section="${key%%.*}"; field="${key#*.}"; sed -n "s/^passwall\.${section}\.${field}=//p" "$state" | head -1 | sed "s/^'//;s/'$//" ;;
      *) exit 1 ;;
    esac ;;
  show) cat "$state" ;;
  export) cat "$state" ;;
  set) pair="$2"; path="${pair%%=*}"; value="${pair#*=}"; awk -v p="$path" -v v="$value" 'BEGIN{done=0} {k=$0; sub(/=.*/,"",k); if(k==p){print k "=\x27" v "\x27"; done=1} else print} END{if(!done) print p "=\x27" v "\x27"}' "$state" >"$state.next"; mv "$state.next" "$state" ;;
  commit|revert) : ;;
  *) exit 1 ;;
esac
EOF_UCI
chmod +x "$TMP/bin/uci"
cat >"$TMP/passwall.state" <<'EOF_STATE'
passwall.s1.address='cdn.example.com'
passwall.s1.remarks='Node A'
EOF_STATE
cat >"$TMP/status.json" <<'EOF_STATUS'
{"best_ips":["104.16.1.1"]}
EOF_STATUS
export PATH="$TMP/bin:$PATH" UCI_FAKE_STATE="$TMP/passwall.state" UCI_WORK_DIR="$TMP/work" CFIP_INIT_DIR="$TMP/init" CFIP_STATUS_DIR="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_FILE="$TMP/status.json" CFIP_LOG_FILE="$TMP/log" CFIP_PASSWALL_STATE_FILE="$TMP/managed.json"
CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
CFIP_SERVICE_LOG="$TMP/services.log"; export CFIP_SERVICE_LOG
cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" '{ip:$ip,domain:$domain,family:$family,success:true,totalMs:40,connectMs:10,tlsMs:10,ttfbMs:20}'; }
result="$(cmd_sync passwall)"
echo "$result" | jq -e '.success==true and .restartCount==1' >/dev/null
test "$(grep -c '^restart$' "$TMP/services.log")" -eq 1
test "$(grep -c '^stop$' "$TMP/services.log")" -eq 1
echo 'manual sync single-restart behavior passed'
