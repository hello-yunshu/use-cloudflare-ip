#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
grep -q '^PKG_VERSION:=2.0.0-dev$' "$PKG/Makefile"
grep -q 'PKGARCH:=all' "$PKG/Makefile"
grep -q '^/etc/config/cf_ip$' "$PKG/Makefile"
grep -q '^/etc/cf_ip$' "$PKG/Makefile"
grep -q 'po2lmo' "$PKG/Makefile"
grep -q 'cf_ip_publisher' "$PKG/Makefile"
grep -q '/etc/init.d/cf_ip_publisher stop' "$PKG/Makefile"
grep -q "sed -i 's/^PKG_VERSION:=2.0.0-dev\$/PKG_VERSION:=2.0.0.1/'" "$ROOT/.github/workflows/ci.yml"
grep -q 'ipk) tar -tf' "$ROOT/.github/workflows/ci.yml"
grep -q 'apk adbdump' "$ROOT/.github/workflows/ci.yml"
echo 'legacy package/conffiles contract passed'
