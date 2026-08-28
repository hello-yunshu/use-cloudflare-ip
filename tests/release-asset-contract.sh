#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="${1:?release directory required}"; VERSION="${2:?package version required}"
checksum="$ROOT_DIR/sha256sums.txt"
test -f "$checksum"
assets=()
for pattern in "luci-app-cloudflare-ip*.ipk" "luci-app-cloudflare-ip*.apk"; do
  found=()
  while IFS= read -r file; do found+=("$file"); done < <(find "$ROOT_DIR" -type f -name "$pattern" ! -name sha256sums.txt)
  test "${#found[@]}" -eq 1 || { echo "expected one release asset for $pattern" >&2; exit 1; }
  assets+=("${found[0]}")
done
for file in "${assets[@]}"; do
  base="${file##*/}"
  test "$(grep -Ec "^[0-9a-fA-F]{64}[[:space:]][[:space:]]${base}$" "$checksum")" -eq 1 || { echo "missing relative checksum for $base" >&2; exit 1; }
  expected="$(awk -v b="$base" '$2==b {print $1}' "$checksum")"
  actual="$(sha256sum "$file" | awk '{print $1}')"
  test "$expected" = "$actual" || { echo "checksum mismatch: $base" >&2; exit 1; }
done
test "$(grep -E '^[^/]+$' "$checksum" | wc -l | tr -d ' ')" -ge "${#assets[@]}"
echo 'release asset contract passed'
