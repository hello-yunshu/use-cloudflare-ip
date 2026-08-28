#!/usr/bin/env bash
# Base-package fallback. The Rill integration is provided by the optional
# luci-app-cloudflare-ip-rill package and must never be required for legacy use.

cfip_rill_status_json() { jq -cn '{available:false,state:"disabled",mode:(env.CFIP_RILL_MODE // "off")}'; }
cfip_rill_rank_shadow() { return 1; }
cfip_rill_feedback() { return 1; }
