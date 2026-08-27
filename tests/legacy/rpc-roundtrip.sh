#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/backend" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$RPC_CALLS"
case "$1" in
  --oc-list-backups) printf '{"success":true,"backups":[{"id":"20260827120000"}]}\n' ;;
  --oc-restore-backup) printf '{"success":true,"restored":"%s"}\n' "$2" ;;
  --oc-delete-backup) printf '{"success":true,"deleted":"%s"}\n' "$2" ;;
esac
EOF
chmod +x "$TMP/backend"
cat >"$TMP/jsonfilter" <<'EOF'
#!/bin/sh
value=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = -s ]; then value="$2"; shift 2; else shift; fi
done
printf '%s\n' "$value" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
EOF
chmod +x "$TMP/jsonfilter"
export RPC_CALLS="$TMP/calls" CF_IP_AUTO_BIN="$TMP/backend" PATH="$TMP:$PATH"
rpc() { sh "$PKG/root/usr/libexec/rpcd/cf_ip" call "$1"; }
rpc oc-list-backups | jq -e '.success and .backups[0].id=="20260827120000"' >/dev/null
printf '%s\n' '{"id":"20260827120000"}' | rpc oc-restore-backup | jq -e '.success and .restored=="20260827120000"' >/dev/null
printf '%s\n' '{"id":"20260827120000"}' | rpc oc-delete-backup | jq -e '.success and .deleted=="20260827120000"' >/dev/null
test "$(wc -l <"$RPC_CALLS" | tr -d ' ')" -eq 3
grep -q -- '--oc-restore-backup 20260827120000' "$RPC_CALLS"
grep -q -- '--oc-delete-backup 20260827120000' "$RPC_CALLS"
echo 'legacy RPC backup roundtrip dispatch passed'
