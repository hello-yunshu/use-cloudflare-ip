#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MENU="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/luci/menu.d/luci-app-cloudflare-ip.json"
CONTROLLER="$ROOT/package/luci-app-cloudflare-ip/root/usr/lib/lua/luci/controller/cloudflare-ip.lua"
jq empty "$MENU"
if jq -e 'has("admin/services/cf_ip/passwall") or has("admin/services/cf_ip/openclash")' "$MENU" >/dev/null; then exit 1; fi
grep -Fq 'nixio.fs.access' "$CONTROLLER"
grep -Fq 'id = "passwall"' "$CONTROLLER"
grep -Fq 'id = "openclash"' "$CONTROLLER"
grep -Fq 'p.id},' "$CONTROLLER"
echo 'Installed-aware LuCI routing contract passed'
