#!/usr/bin/env bash
set -euo pipefail

if (( $# == 0 )); then
  echo "usage: openwrt-build-diagnostic.sh <target> [<target> ...]" >&2
  exit 2
fi
targets=("$@")
jobs="${BUILD_JOBS:-$(($(nproc)+1))}"

if make -j"$jobs" "${targets[@]}"; then
  exit 0
else
  fast_rc=$?
fi

echo "::error::Fast parallel OpenWrt build failed: ${targets[*]}"
echo "::group::OpenWrt config at fast-build failure"
if [[ -f .config ]]; then
  cat .config
else
  echo "No .config found in $(pwd)"
fi
echo "::endgroup::"

for target in "${targets[@]}"; do
  echo "::group::Serial verbose diagnostic: $target"
  if make -j1 "$target" V=s; then
    diagnostic_rc=0
  else
    diagnostic_rc=$?
  fi
  echo "Serial diagnostic exit code for $target: $diagnostic_rc"
  echo "::endgroup::"
done

exit "$fast_rc"
