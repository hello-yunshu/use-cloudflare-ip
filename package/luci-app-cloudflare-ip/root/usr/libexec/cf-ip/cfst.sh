#!/usr/bin/env bash
# CFST process boundary: one task, one input, one invocation.

cfip_cfst_version() {
    local binary="${1:-${CFIP_WORK_DIR:-/usr/bin}/cfst/cfst}" version_file output version
    version_file="${binary}_version.txt"
    if [[ -s "$version_file" ]]; then
        version="$(head -n 1 "$version_file" | tr -d '\r')"
        [[ "$version" =~ ^v?[0-9]+([.][0-9]+)+([.-][A-Za-z0-9._-]+)?$ ]] && { printf '%s' "$version"; return 0; }
    fi
    [[ -x "$binary" ]] || return 1
    output="$(cfip_run_with_timeout 3 "$binary" --version 2>&1 || true)"
    version="$(printf '%s\n' "$output" | grep -Eo 'v?[0-9]+([.][0-9]+)+' | head -n 1 || true)"
    [[ -n "$version" ]] || return 1
    printf '%s' "$version"
}

cfip_cfst_invocation_record() {
    CFIP_CFST_INVOCATION_COUNT=$(( ${CFIP_CFST_INVOCATION_COUNT:-0} + 1 ))
}
