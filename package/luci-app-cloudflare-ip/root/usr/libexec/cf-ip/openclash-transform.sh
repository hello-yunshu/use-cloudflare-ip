#!/usr/bin/env bash
# OpenClash transformer adapter.  The caller owns service lifecycle, snapshots,
# health checks, rollback, and commit.

cfip_openclash_transform_selected() {
    local selected="$1"
    [[ -s "$selected" && -x "${CFIP_LEGACY_BIN:-/usr/bin/cf-ip-auto-legacy}" ]] || return 1
    CFIP_PURE_APPLY=true "$CFIP_LEGACY_BIN" --apply-selected "$selected" openclash >/dev/null 2>&1
}
