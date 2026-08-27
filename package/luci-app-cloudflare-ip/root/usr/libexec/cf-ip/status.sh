#!/usr/bin/env bash
# Status serialization is owned by the orchestrator so it can include the
# complete legacy compatibility surface and all run-phase fields.

cfip_status_is_v2() { [[ -s "${CFIP_STATUS_FILE:-/etc/cf_ip/status.json}" ]] && jq -e '.schemaVersion == 2' "${CFIP_STATUS_FILE:-/etc/cf_ip/status.json}" >/dev/null 2>&1; }
