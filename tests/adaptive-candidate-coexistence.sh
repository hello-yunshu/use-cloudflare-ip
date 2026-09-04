#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
adaptive="$(<"$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/adaptive-measurement.sh")"
runner="$(<"$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2")"
grep -F 'Native adaptive measurement. It schedules probes only' <<<"$adaptive" >/dev/null
grep -F 'Native selection remains the safety boundary' <<<"$runner" >/dev/null
grep -F 'CFIP_ADAPTIVE_AUDIT_DUE' <<<"$runner" >/dev/null
! grep -F 'CFIP_ADAPTIVE_PARTITION' <<<"$adaptive" >/dev/null
! grep -F 'cfip_rill_' <<<"$adaptive" >/dev/null
echo 'Adaptive and Candidate coexistence preserves Native authority and one learner boundary'
