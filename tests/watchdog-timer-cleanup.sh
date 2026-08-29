#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "$$" "$*" >>"${CFIP_TEST_SLEEP_LOG:?}"
exec /bin/sleep "$@"
EOF
chmod +x "$TMP/bin/sleep"
export PATH="$TMP/bin:$PATH" CFIP_TEST_SLEEP_LOG="$TMP/sleeps"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"

run_batch() {
    local mode="$1" i pid args state
    if [[ "$mode" == fallback ]]; then export CFIP_DISABLE_SETSID=true; else unset CFIP_DISABLE_SETSID; fi
    : >"$CFIP_TEST_SLEEP_LOG"
    for i in {1..25}; do
        cfip_run_with_timeout 30 true
    done
    while IFS=$'\t' read -r pid args; do
        [[ "$args" == 30 || "$args" == 0.1 ]] || { echo "unexpected timer invocation: $pid $args" >&2; exit 1; }
        [[ "$args" == 0.1 ]] && continue
        if kill -0 "$pid" 2>/dev/null; then
            echo "watchdog timer survived: pid=$pid" >&2
            exit 1
        fi
        state="$(ps -p "$pid" -o stat= 2>/dev/null || true)"
        [[ -z "$state" || "$state" == Z* ]] || { echo "watchdog timer survived: pid=$pid state=$state" >&2; exit 1; }
    done <"$CFIP_TEST_SLEEP_LOG"
}

run_batch normal
if [[ -r /proc/self/task/$$/children ]]; then
    run_batch fallback
fi
echo 'watchdog timer cleanup contract passed'
