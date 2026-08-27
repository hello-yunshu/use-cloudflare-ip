#!/usr/bin/env bash
set -euo pipefail
PACKAGE="${1:?package path required}"; KIND="${2:?ipk or apk required}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
case "$KIND" in
  ipk)
    listing="$TMP/listing"
    members="$(tar -tf "$PACKAGE" | awk '{sub(/^\.\//, ""); if ($0 ~ /^(control|data)\.tar/ && !seen[$0]++) print}')"
    control_member="$(printf '%s\n' "$members" | awk '/^control\.tar/ {print; exit}')"
    data_member="$(printf '%s\n' "$members" | awk '/^data\.tar/ {print; exit}')"
    test -n "$control_member" || { echo 'missing control.tar.* member in IPK' >&2; exit 1; }
    test -n "$data_member" || { echo 'missing data.tar.* member in IPK' >&2; exit 1; }
    tar -xf "$PACKAGE" -C "$TMP" "./$control_member"
    tar -xf "$PACKAGE" -C "$TMP" "./$data_member"
    {
      tar -tf "$TMP/$control_member"
      tar -tf "$TMP/$data_member"
    } | sed 's#^\./##' >"$listing"
    ;;
  apk)
    listing="$TMP/listing"
    mkdir -p "$TMP/root"
    # OpenWrt's apk is an apk-tools v3 build.  Global options must precede
    # the subcommand, CI-built packages are intentionally not trusted by the
    # target root's keyring, and --destination is the extract target (whereas
    # --root selects an apk database root).
    "${APK:-apk}" --allow-untrusted extract --destination "$TMP/root" "$PACKAGE" >/dev/null
    (cd "$TMP/root" && find . -type f -print | sed 's#^\./##') >"$listing"
    ;;
  *) echo "unsupported package kind: $KIND" >&2; exit 2 ;;
esac
required=(
  usr/bin/cf-ip-auto
  usr/bin/cf-ip-auto-legacy
  usr/libexec/rpcd/cf_ip
  etc/init.d/cf_ip
  etc/init.d/cf_ip_publisher
  etc/config/cf_ip
  usr/share/luci/menu.d/luci-app-cloudflare-ip.json
  usr/share/rpcd/acl.d/luci-app-cloudflare-ip.json
  usr/lib/lua/luci/controller/cloudflare-ip.lua
  www/luci-static/resources/cloudflare-ip/cloudflare-ip.css
  www/luci-static/resources/view/cloudflare-ip/overview.js
  usr/libexec/cf-ip/common.sh
  usr/libexec/cf-ip/transaction.sh
)
for path in "${required[@]}"; do
  grep -Fxq "$path" "$listing" || { echo "missing package path: $path" >&2; exit 1; }
done
grep -Eq '(^|/)conffiles$' "$listing" || { echo 'missing conffiles metadata' >&2; exit 1; }
test "$(grep -Ec 'usr/libexec/cf-ip/[^/]+\.sh$' "$listing")" -ge 10
test "$(grep -Ec 'usr/lib/lua/luci/i18n/.*\.lmo$' "$listing")" -ge 1
echo "package content contract passed: $KIND"
