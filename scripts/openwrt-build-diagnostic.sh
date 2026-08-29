#!/usr/bin/env bash
set -euo pipefail

target="${1:?usage: openwrt-build-diagnostic.sh <target>}"
jobs="${BUILD_JOBS:-$(($(nproc)+1))}"

if make -j"$jobs" "$target"; then
  exit 0
else
  fast_rc=$?
fi

echo "::error::Fast parallel OpenWrt build failed: $target"
echo "::group::OpenWrt config at fast-build failure"
if [[ -f .config ]]; then
  cat .config
else
  echo "No .config found in $(pwd)"
fi
echo "::endgroup::"

echo "::group::Serial verbose diagnostic: $target"
if make -j1 "$target" V=s; then
  diagnostic_rc=0
else
  diagnostic_rc=$?
fi
echo "Serial diagnostic exit code: $diagnostic_rc"
echo "::endgroup::"

exit "$fast_rc"
