# Historical Rill integration note

🔄 superseded by Candidate-only architecture. This file records the superseded pre-v3 integration shape. Current Cloudflare
integration uses the package-owned `/usr/bin/rill-runtime` generic IPC v3
Preview surface; it does not download, install, remove, or publish a private
consumer adapter. The old 1.5.3 adapter details below are historical only.

The adapter is consumer-owned and optional. It receives unified local measurements: latency, download, loss, connect, TLS, TTFB, total and `nativeRank`. It never receives remote source ports, domain candidates or endpoint kinds and cannot mutate host config. Modes are off, shadow (default when enabled), and assisted only after qualification.
