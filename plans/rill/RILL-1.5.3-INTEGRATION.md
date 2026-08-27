# RillML 1.5.3 integration

The adapter is consumer-owned and optional. It receives unified local measurements: latency, download, loss, connect, TLS, TTFB, total and `nativeRank`. It never receives remote source ports, domain candidates or endpoint kinds and cannot mutate host config. Modes are off, shadow (default when enabled), and assisted only after qualification.
