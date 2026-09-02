#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UTILS="$ROOT/package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/utils.js"
RPCD="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/rpcd/cf_ip"
ACL="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/rpcd/acl.d/luci-app-cloudflare-ip.json"
grep -Fq "method: 'validate-config'" "$UTILS"
grep -Fq 'return callValidateConfig(candidate).then(requireSuccess);' "$UTILS"
grep -Fq 'buildStagedCandidate' "$UTILS"
grep -Fq 'return safeApply();' "$UTILS"
test "$(grep -n 'return callValidateConfig' "$UTILS" | cut -d: -f1)" -lt "$(grep -n 'return safeApply' "$UTILS" | head -n1 | cut -d: -f1)"
grep -Fq 'validate-config' "$RPCD"
jq -e '."luci-app-cloudflare-ip".read.ubus.cf_ip | index("validate-config") != null' "$ACL" >/dev/null
echo 'LuCI validation RPC-before-apply contract passed'
