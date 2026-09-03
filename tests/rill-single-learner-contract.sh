#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

RILL="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/rill.sh"
command -v rg >/dev/null 2>&1 || { echo 'ripgrep is required for negative contract checks' >&2; exit 1; }
! rg -n 'CFIP_RILL_SOURCE_PARTITION_KEY|CFIP_RILL_REUSE_PARTITION_KEY|cfip_rill_policy_(decide|feedback)|partition_for_kind|state_generation_for_partition' "$RILL" >/dev/null

export CFIP_STATUS_DIR="$TMP" CFIP_RILL_STATE="$TMP/rill-state.json"
export CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/rill-feature-schema-v2.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$RILL"

state="$(jq -cn --arg s '{"handlerStateVersion":2,"featureCount":22,"weights":[],"actions":{}}' \
  '{formatVersion:1,partitions:[{clientIdentityName:"cloudflare-ip",partitionKey:"candidate",handlerSnapshot:{state:($s|explode),stateGeneration:4}},{clientIdentityName:"other-consumer",partitionKey:"other",handlerSnapshot:{state:[],stateGeneration:1}}]}')"
printf '%s\n' "$state" > "$CFIP_RILL_STATE"
cfip_rill_prepare_state
test "$(jq '[.partitions[] | select(.clientIdentityName=="cloudflare-ip")] | length' "$CFIP_RILL_STATE")" = 1
test "$(jq -r '[.partitions[] | select(.clientIdentityName=="cloudflare-ip")][0].partitionKey' "$CFIP_RILL_STATE")" = candidate
test "$(cfip_rill_state_generation)" = 4
echo 'Candidate-only Runtime learner contract passed'
