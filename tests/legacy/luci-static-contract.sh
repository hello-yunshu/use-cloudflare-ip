#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
for class in cfi-badge cfi-log-area cfi-section cfi-cmd-box cfi-btn-group cfi-kv-table cfi-table-wrap cfi-responsive-table cfi-actions; do grep -q "\.$class" "$PKG/htdocs/luci-static/resources/cloudflare-ip/cloudflare-ip.css" || fail "CSS $class missing"; done
for js in "$PKG"/htdocs/luci-static/resources/view/cloudflare-ip/*.js; do node --check "$js" >/dev/null; done
echo 'legacy LuCI static contract passed'
