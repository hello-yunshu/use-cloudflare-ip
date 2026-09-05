# Cloudflare IP 2.3 Docker evidence harness

This harness is bounded MacBook + Docker replay. It reuses the production
`adaptive-measurement.sh` scheduler and audit builder. It does not claim
physical OpenWrt coverage.

Run locally with `bash docker/2.3/run-experiments.sh` or with
`docker compose -f docker/2.3/compose.yaml run --rm adaptive-replay`.

Generated evidence is bounded and marked with `environment` and `timingMode`.
Replay or synthetic timings must not be presented as real network latency or
wall-clock savings. The replay summary uses `meanReplay*` fields for this
reason. A separate opt-in `run-real-mac-evidence.sh` path records only bounded
HTTP status and measured duration when the host is actually macOS with a
running Docker daemon; otherwise it reports `NOT AVAILABLE` and creates no
fake evidence.
The harness only produces evidence and recommendation candidates; it never
writes UCI, tunes parameters automatically, uploads network data, or trains a
policy. Physical OpenWrt and soak remain `SKIPPED (user-approved)`.
