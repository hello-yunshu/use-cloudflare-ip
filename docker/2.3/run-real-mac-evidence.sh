#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="${1:-$ROOT/docker/2.3/results/real-mac-evidence.json}"
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'MacBook Docker Real Execution — NOT AVAILABLE IN THIS ENVIRONMENT' >&2
    exit 2
fi
command -v docker >/dev/null 2>&1 || { echo 'MacBook Docker Real Execution — Docker is unavailable' >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo 'MacBook Docker Real Execution — Docker daemon is unavailable' >&2; exit 2; }
docker compose -f "$ROOT/docker/2.3/compose.yaml" build adaptive-replay
docker run --rm \
    -e HOST_PLATFORM="$(uname -s -m)" \
    -e DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}" \
    -e CFIP_REAL_MAX_PROBES=4 \
    -e CFIP_REAL_TOTAL_TIMEOUT_SECONDS=20 \
    -v "$ROOT:/workspace/repo" \
    -w /workspace/repo \
    cloudflare-ip-adaptive-replay:ci \
    bash docker/2.3/collect-real-evidence.sh "$OUTPUT"
