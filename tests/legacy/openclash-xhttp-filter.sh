#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
bash "$ROOT/tests/openclash-xhttp-filter.sh" >/dev/null
echo 'OpenClash XHTTP filter preservation passed'
