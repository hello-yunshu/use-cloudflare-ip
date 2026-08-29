#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
modes=()
command -v setsid >/dev/null 2>&1 && modes+=(setsid)
[[ -r /proc/self/task/$$/children ]] && modes+=(fallback)
if ((${#modes[@]})); then for mode in "${modes[@]}"; do
    marker="$TMP/$mode"
    set +e
    if [[ "$mode" == fallback ]]; then export CFIP_DISABLE_SETSID=true; else unset CFIP_DISABLE_SETSID; fi
    cfip_run_with_timeout 1 bash -c 'printf stage-1 >"$1"; (sleep 3; printf stage-2 >>"$1") & wait' bash "$marker"
    rc=$?
    set -e
    test "$rc" -eq 124
    sleep 4
    test "$(cat "$marker")" = stage-1
done; fi
echo 'external operation timeout tree contract passed'
