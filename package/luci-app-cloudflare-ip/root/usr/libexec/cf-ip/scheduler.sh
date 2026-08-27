#!/usr/bin/env bash
# Scheduler-facing contract kept separate from source acquisition. The current
# implementation lives in source.sh so source records and allocation use one
# tested data model; these guards are shared by callers and fixtures.

cfip_scheduler_budget_valid() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] || return 1
    ((10#$1 >= 100 && 10#$1 <= 512))
}

cfip_scheduler_exact_host() {
    local ip="$1"
    if [[ "$ip" == *:* ]]; then printf '%s/128\n' "$ip"; else printf '%s/32\n' "$ip"; fi
}
